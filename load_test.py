import asyncio
import httpx
import time

API_URL = "http://127.0.0.1:8000/api/chat"
SIMULTANEOUS_USERS = 10
QUERY = "What is phishing and how do I protect my system?"

async def make_request(user_id: int, client: httpx.AsyncClient):
    print(f"[User {user_id}] Sending query...")
    start = time.time()
    try:
        response = await client.post(
            API_URL, 
            json={"query": QUERY},
            timeout=30.0 # Wait up to 30s
        )
        data = response.json()
        duration = time.time() - start
        print(f"[User {user_id}] Response received in {duration:.2f}s | Server reported processing time: {data.get('time_taken')}s")
        return duration
    except Exception as e:
        print(f"[User {user_id}] Error: {str(e)}")
        return None

async def main():
    print(f"--- Starting Load Test ---")
    print(f"Goal: {SIMULTANEOUS_USERS} simultaneous users hitting '{API_URL}'")
    
    # We use AsyncClient to fire requests at the exact same time
    async with httpx.AsyncClient() as client:
        tasks = [make_request(i+1, client) for i in range(SIMULTANEOUS_USERS)]
        start_time = time.time()
        
        # Run all requests simultaneously
        results = await asyncio.gather(*tasks)
        
        total_time = time.time() - start_time
        
    successes = [r for r in results if r is not None]
    
    print(f"\n--- Load Test Results ---")
    print(f"Total time elapsed: {total_time:.2f}s")
    print(f"Successful requests: {len(successes)}/{SIMULTANEOUS_USERS}")
    if successes:
        print(f"Average response time: {sum(successes) / len(successes):.2f}s")
        print(f"Max response time: {max(successes):.2f}s")

if __name__ == "__main__":
    asyncio.run(main())
