import asyncio
import json
import websockets
from nats.aio.client import Client as NATS
import datetime
from alpaca.data.live import StockDataStream
import json

# Replace these with your Alpaca API credentials and endpoint details.
ALPACA_API_KEY = 'AKH7HWB529BTQJDMDLZV'
ALPACA_SECRET_KEY = 'RDZItO83Vw7eFv7ccpnXju64ZHT4riMc2wsKgjw1'
ALPACA_WS_URL = 'wss://stream.data.alpaca.markets/v2/test'

from nats.aio.client import Client as NATS
nc = None  # Global variable to hold the NATS connection
async def connect_nats():
    global nc
    nc = NATS()
    await nc.connect("nats://localhost:4222")

def json_serializer(obj):
    if isinstance(obj, (datetime.datetime, datetime.date)):
        return obj.isoformat()  # Converts datetime to ISO 8601 string.
    raise TypeError("Type not serializable")

wss_client = StockDataStream(api_key=ALPACA_API_KEY , secret_key=ALPACA_SECRET_KEY, url_override=ALPACA_WS_URL)
save_data = None
# async handler
async def bars_data_handler(data):
    # bars data will arrive here
    save_data=data
    print(data)
    bar_timestamp = data.timestamp
    current_timestamp = datetime.datetime.now(datetime.timezone.utc)
    time_diff = current_timestamp - bar_timestamp
    print(60 - time_diff.total_seconds())
    print(type(data))
    
    # Convert the data to JSON (ensure your data is serializable)
    try:
        message = json.dumps(data.__dict__, default=json_serializer)  # or convert data appropriately if it's not a dict
    except Exception as e:
        print("Error serializing data:", e)
        return
    
    # Publish the message to NATS under the subject "bars.data"
    await nc.publish("bars.data", message.encode())

#wss_client.subscribe_bars(bars_data_handler, "FAKEPACA")

#wss_client.run()

async def main():
    # Connect to the local NATS server.
    await connect_nats()
    
    # Subscribe to bars and set the callback handler.
    wss_client.subscribe_bars(bars_data_handler, "FAKEPACA")
    
    # Run the Alpaca websocket client.
    await wss_client._run_forever()

if __name__ == "__main__":
    asyncio.run(main())