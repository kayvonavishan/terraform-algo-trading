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

# async def run():
#     nc = NATS()
#     # Replace <NATS_EC2_IP> with the actual IP address or DNS name of your NATS server
#     await nc.connect("nats://natsuser:natspassword@54.226.179.43:4222")
    
#     async def message_handler(msg):
#         print("Received message:", msg.data.decode())
    
#     # Subscribe to the subject "bars.data"
#     await nc.subscribe("bars.data", cb=message_handler)
    
#     # Keep the subscriber running
#     while True:
#         await asyncio.sleep(1)

# if __name__ == '__main__':
#     asyncio.run(run())

# Global buffer to hold 1-min bars for the current aggregation window.
current_window_bars = []

def get_window_start(timestamp):
    """
    Returns the start of the 15-min window for the given timestamp.
    For instance, if the timestamp is 10:07, the window start is 10:00.
    """
    window_start_minute = (timestamp.minute // 15) * 15
    return timestamp.replace(minute=window_start_minute, second=0, microsecond=0)

def aggregate_bars(bars):
    """
    Aggregates a list of 1-min bars into a single 15-min bar.
    
    Each bar is assumed to be a dictionary with at least the following keys:
      - 'agg_timestamp': the timestamp (already in EST)
      - 'open', 'high', 'low', 'close', 'volume', 'trade_count', 'vwap'
    
    The aggregation is done as follows:
      - Open: the open of the first bar.
      - High: the maximum high.
      - Low: the minimum low.
      - Close: the close of the last bar.
      - Volume and trade_count: summed.
      - VWAP: volume-weighted average price, computed as the sum(vwap * volume) divided by total volume.
    """
    df = pd.DataFrame(bars)
    df = df.sort_values('agg_timestamp')
    
    total_volume = df['volume'].sum()
    agg_bar = {
        'symbol': df.iloc[0]['symbol'],
        'open': df.iloc[0]['open'],
        'high': df['high'].max(),
        'low': df['low'].min(),
        'close': df.iloc[-1]['close'],
        'volume': total_volume,
        'trade_count': df['trade_count'].sum(),
        'vwap': (df['vwap'] * df['volume']).sum() / total_volume if total_volume != 0 else None,
        # Set the aggregated timestamp as the start of the window
        'agg_timestamp': get_window_start(df.iloc[0]['agg_timestamp'])
    }
    return agg_bar

async def process_live_bar(live_bar, historical_df):
    """
    Processes a live 1-min bar.
    
    Appends the bar to a buffer, and if the bar is at the cutoff minute 
    (e.g., minute 14, 29, 44, or 59) it aggregates the buffered bars into
    a 15-min bar and appends that to the historical DataFrame.
    
    Parameters:
      live_bar (dict): The incoming 1-minute bar. It must include an 'agg_timestamp'
                       key as a timezone-aware datetime (in EST).
      historical_df (pd.DataFrame): The DataFrame of historical 15-min bars.
    
    Returns:
      The updated historical_df.
    """
    global current_window_bars
    # Append the live bar to the current window buffer.
    current_window_bars.append(live_bar)
    print(f"current_window_bars = {current_window_bars}")
    # Check if the incoming bar is the final bar for the current 15-min window.
    # The cutoff is when minute % 15 equals 14 (e.g., 14, 29, 44, 59).
    if live_bar['agg_timestamp'].minute % 15 == 14:
        # When the cutoff is reached, aggregate the current window.
        agg_bar = aggregate_bars(current_window_bars)
        #historical_df = historical_df.append(agg_bar, ignore_index=True)
        historical_df = pd.concat([historical_df, pd.DataFrame([agg_bar])], ignore_index=True)
        print(f"Aggregated bar for window starting at {agg_bar['agg_timestamp']}: {agg_bar}")
        # Clear the buffer for the next window.
        current_window_bars = []
    
    return historical_df

# Example asynchronous message handler for live data via NATS.
async def live_data_handler(msg, historical_df):
    """
    Handler for incoming NATS messages containing 1-min bar data.
    It decodes the message, converts the timestamp (if needed), and processes the bar.
    """
    import json
    live_bar = json.loads(msg.data.decode())
    
    # Convert the 'timestamp' to a proper datetime if necessary and rename it:
    # (Assume the live bar data has a key 'timestamp'; convert it and rename to 'agg_timestamp')
    live_bar['agg_timestamp'] = pd.to_datetime(live_bar.pop('timestamp'))
    
    # If necessary, convert the timestamp to US/Eastern (assuming it comes in as UTC):
    live_bar['agg_timestamp'] = live_bar['agg_timestamp'].tz_convert('US/Eastern')
    
    print(f"decoded live bar = {live_bar}")
    
    # Process the bar and update historical_df if the window is complete.
    historical_df = await process_live_bar(live_bar, historical_df)
    return historical_df

# Example asyncio loop to subscribe to live data from a NATS server.
async def run_live_trading(historical_df):
    from nats.aio.client import Client as NATS
    nc = NATS()
    # Connect to your NATS server (update with your credentials/endpoint).
    await nc.connect("nats://natsuser:natspassword@54.226.179.43:4222")
    
    async def message_handler(msg):
        print(msg)
        nonlocal historical_df
        historical_df = await live_data_handler(msg, historical_df)
    
    # Subscribe to the subject where 1-min bar messages are published.
    await nc.subscribe("bars.data", cb=message_handler)
    
    # Keep the subscription alive.
    while True:
        await asyncio.sleep(1)

# In your main program, you would load your historical 15-min DataFrame (e.g., from get_stock_data())
# and then run the live data processing loop.
if __name__ == '__main__':
    # Assume you already have historical_df from historical data (15-min bars).
    # For example, if you used get_stock_data() from your earlier code:
    import json
    historical_df = data_dict  # Replace with your loaded DataFrame.
    
    # Run the live trading event loop.
    asyncio.run(run_live_trading(historical_df))
