import os
from mlb_data import get_mlb_data, get_mlb_realized_slate
import datetime
import pandas as pd

# If we get too far into the future, gonna need to change this value
# to a more recent one
data = get_mlb_data(1953)
ids = {x["StartDate"][:10]: x["Id"] for x in data["Periods"]}

most_recent = datetime.date(1900, 1, 1)
for file in os.listdir("./data/mlb_realized_slates"):
    date = datetime.date.fromisoformat(file[:10])
    if date > most_recent:
        most_recent = date

most_recent_id = ids[str(most_recent)]
# Get most recently availiable ID
max_id = max(ids.values())
# Start from the ID one past the one we have, and range is not inclusive on the end
# so we won't get the current projection only ID
for ID in range(most_recent_id + 1, max_id):
    try:
        date, realized_slate = get_mlb_realized_slate(ID)
        realized_slate.to_csv(f"./data/mlb_realized_slates/{date}.csv", index=False)
    except ValueError as e:
        print(e)

frames = []
for file in os.listdir("./data/mlb_realized_slates"):
    data = pd.read_csv(f"./data/mlb_realized_slates/{file}")
    data["Date"] = file[0:10]
    frames.append(data)

frame = pd.concat(frames)
frame = frame[
    [
        "Name",
        "Position",
        "Salary",
        "Game",
        "Team",
        "Opponent",
        "Order",
        "Projection",
        "Scored",
        "Date",
    ]
]
frame.to_csv("./data/mlb_hist.csv", index=False)
