"""
news_module.py – Fetches and formats real-time cybersecurity news from NewsAPI.
Free tier: 100 requests/day. Register at https://newsapi.org/
"""

import requests
from config import NEWS_API_KEY, NEWS_QUERY, NEWS_PAGE_SIZE
import untrusted


def fetch_cybersecurity_news():
    """
    Fetch latest cybersecurity articles from NewsAPI.
    Returns: (articles list, error string or None)
    """
    if not NEWS_API_KEY:
        return None, (
            "NEWS_API_KEY is not set.\n"
            "Get a free key at https://newsapi.org/ and add it to your .env file."
        )

    url = "https://newsapi.org/v2/everything"
    params = {
        "q": NEWS_QUERY,
        "sortBy": "publishedAt",
        "language": "en",
        "pageSize": NEWS_PAGE_SIZE,
        "apiKey": NEWS_API_KEY,
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()

        articles = data.get("articles", [])
        if not articles:
            return None, "No recent cybersecurity news articles found."

        return articles, None

    except requests.exceptions.ConnectionError:
        return None, "Network error. Please check your internet connection."
    except requests.exceptions.Timeout:
        return None, "News API request timed out. Try again later."
    except requests.exceptions.HTTPError as e:
        if response.status_code == 401:
            return None, "Invalid NEWS_API_KEY. Please check your .env file."
        return None, f"HTTP error from NewsAPI: {e}"
    except Exception as e:
        return None, f"Unexpected error fetching news: {str(e)}"


def format_articles_for_llm(articles: list) -> str:
    """
    Convert raw API articles into a readable string for LLM summarization.
    """
    formatted_parts = []
    guard = untrusted.guard_enabled()

    for i, article in enumerate(articles[:NEWS_PAGE_SIZE], start=1):
        title       = article.get("title", "Unknown Title")
        source      = article.get("source", {}).get("name", "Unknown Source")
        published   = article.get("publishedAt", "")[:10]  # just YYYY-MM-DD
        description = article.get("description") or "No description available."
        # Truncate long descriptions to avoid token overload
        description = description[:500]
        if guard:
            # Headlines and descriptions come from arbitrary third parties.
            title = untrusted.sanitize(title, 200)
            source = untrusted.sanitize(source, 80)
            published = untrusted.sanitize(published, 10)
            description = untrusted.sanitize(description, 500)

        formatted_parts.append(
            f"Article {i}:\n"
            f"  Title: {title}\n"
            f"  Source: {source}\n"
            f"  Published: {published}\n"
            f"  Description: {description}\n"
        )

    joined = "\n".join(formatted_parts)
    if guard:
        return f"{untrusted.DATA_ONLY_NOTE}\n{untrusted.spotlight(joined, 'news', 6000)}"
    return joined
