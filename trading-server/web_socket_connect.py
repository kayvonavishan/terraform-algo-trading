import asyncio
from nats.aio.client import Client as NATS
from datetime import datetime, timedelta
import pandas as pd

from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame

def get_stock_data(symbols, start_date, end_date=None):
    """
    Retrieve historical stock bar data for given symbols between start_date and end_date.
    
    Parameters:
      symbols (list): List of stock symbols (e.g., ["TQQQ"]).
      start_date (datetime.date or datetime): Start date for the data.
      end_date (datetime.date or datetime), optional: End date for the data. If None, data will be retrieved up to now.
      
    Returns:
      DataFrame or dict of DataFrames: If one symbol is provided, returns a single DataFrame.
                                       Otherwise, returns a dictionary mapping each symbol to its DataFrame.
    """
    client = StockHistoricalDataClient(api_key=ALPACA_API_KEY, secret_key=ALPACA_SECRET_KEY)
    
    # Define the timeframe: using 15-minute bars in this example
    historical_data_timeframe = TimeFrame.Minute
    historical_data_timeframe.amount_value = 15
    
    # Build request parameters
    request_params = StockBarsRequest(
        symbol_or_symbols=symbols,
        timeframe=historical_data_timeframe,
        start=start_date,
        end=end_date
    )
    
    # Fetch the data
    bars = client.get_stock_bars(request_params)
    
    # Process each symbol's data into a DataFrame
    data_dict = {}
    for symbol in symbols:
        symbol_data = bars.data[symbol]
        # Convert records to dictionaries if they are not already
        symbol_data = [dict(record) for record in symbol_data]
        df = pd.DataFrame(symbol_data)
        
        # Rename and set the timestamp as index
        df.rename(columns={'timestamp': 'agg_timestamp'}, inplace=True)
        df.set_index('agg_timestamp', inplace=True)
        
        # Convert the index from UTC to US/Eastern timezone
        df.index = df.index.tz_convert('US/Eastern')
        
        # Filter rows: keep only times between 9:30 AM and 3:45 PM EST
        df = df.between_time('09:30', '15:45')
        data_dict[symbol] = df
    
    # Return a single DataFrame if only one symbol was provided; otherwise, return a dict
    if len(symbols) == 1:
        return data_dict[symbols[0]]
    return data_dict

current_datetime = datetime.now()
current_date = current_datetime.date()
current_date_minus_15 = current_date - timedelta(days=15)
symbol = "TQQQ"


ALPACA_API_KEY = 'AKH7HWB529BTQJDMDLZV'
ALPACA_SECRET_KEY = 'RDZItO83Vw7eFv7ccpnXju64ZHT4riMc2wsKgjw1'

data_dict = get_stock_data(symbols=[symbol], start_date=current_date_minus_15)

async def run():
    nc = NATS()
    # Replace <NATS_EC2_IP> with the actual IP address or DNS name of your NATS server
    await nc.connect("nats://natsuser:natspassword@54.226.179.43:4222")
    
    async def message_handler(msg):
        print("Received message:", msg.data.decode())
    
    # Subscribe to the subject "bars.data"
    await nc.subscribe("bars.data", cb=message_handler)
    
    # Keep the subscriber running
    while True:
        await asyncio.sleep(1)

if __name__ == '__main__':
    asyncio.run(run())
