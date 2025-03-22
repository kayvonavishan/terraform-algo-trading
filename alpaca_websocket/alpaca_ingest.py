import asyncio
import json
import websockets
from nats.aio.client import Client as NATS

# Replace these with your Alpaca API credentials and endpoint details.
ALPACA_API_KEY = 'AKH7HWB529BTQJDMDLZV'
ALPACA_SECRET_KEY = 'RDZItO83Vw7eFv7ccpnXju64ZHT4riMc2wsKgjw1'
ALPACA_WS_URL = 'wss://stream.data.alpaca.markets/v2/test'

# NATS server address (Instance 2 public/private IP)
NATS_SERVER = "nats://<INSTANCE_2_IP>:4222"
NATS_SUBJECT = "alpaca.market.data"

async def alpaca_websocket(nc):
    async with websockets.connect(ALPACA_WS_URL) as ws:
        # Authenticate if required (check Alpaca docs for the exact payload)
        auth_msg = {
            "action": "authenticate",
            "data": {
                "key_id": ALPACA_API_KEY,
                "secret_key": ALPACA_SECRET_KEY
            }
        }
        await ws.send(json.dumps(auth_msg))
        response = await ws.recv()
        print("Auth response:", response)

        # Subscribe to a market data channel (adjust as per your needs)
        subscribe_msg = {
            "action": "subscribe",
            "trades": ["AAPL"],
            "quotes": ["AAPL"]
        }
        await ws.send(json.dumps(subscribe_msg))
        print("Subscribed to AAPL market data.")

        # Ingest and forward data to NATS
        async for message in ws:
            print("Received data:", message)
            # Publish the data to NATS
            await nc.publish(NATS_SUBJECT, message.encode())

async def main():
    nc = NATS()
    await nc.connect(servers=[NATS_SERVER])
    try:
        await alpaca_websocket(nc)
    except Exception as e:
        print("Error:", e)
    finally:
        await nc.drain()

if __name__ == "__main__":
    asyncio.run(main())
