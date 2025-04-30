import os
import asyncio
import json
import websockets
import boto3
from nats.aio.client import Client as NATS
import datetime
from alpaca.data.live import StockDataStream
import json

def load_local_config(path: str) -> dict:
    """Read simple key=value lines into a dict."""
    cfg = {}
    with open(path, "r") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                cfg[k.strip()] = v.strip()
    return cfg

def load_symbols_from_s3(bucket: str, key: str):
    s3 = boto3.client("s3")
    obj = s3.get_object(Bucket=bucket, Key=key)
    content = obj["Body"].read().decode("utf-8")
    return [s.strip() for s in content.split(",") if s.strip()]


# -----------------------------------------------------------------------------
# Main script variables
# -----------------------------------------------------------------------------
# Path to the config file written by your EC2 user-data
CONFIG_PATH = "/home/ec2-user/deployment_config.txt"
S3_KEY      = "configs/sandbox_sumbols.txt"   # your symbols file

# Replace these with your Alpaca API credentials and endpoint details.
ALPACA_API_KEY = 'AKH7HWB529BTQJDMDLZV'
ALPACA_SECRET_KEY = 'RDZItO83Vw7eFv7ccpnXju64ZHT4riMc2wsKgjw1'
ALPACA_WS_URL = 'wss://stream.data.alpaca.markets/v2/test'

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

async def main():
    # read from S3 using the bucket pulled from the local config
    symbols = load_symbols_from_s3(AWS_S3_BUCKET, S3_KEY)
    print(f"Subscribing to symbols: {symbols}")

    # Connect to the local NATS server.
    await connect_nats()
    
    # Subscribe to bars and set the callback handler.
    wss_client.subscribe_bars(bars_data_handler, symbols)
    
    # Run the Alpaca websocket client.
    await wss_client._run_forever()

if __name__ == "__main__":
    asyncio.run(main())