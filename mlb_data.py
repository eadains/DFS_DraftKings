import pandas as pd
import numpy as np
import requests
import json
from difflib import get_close_matches
import os


def get_mlb_data(periodId):
    # IF THERE ARE EVER ANY STRANGE DATA ERRORS, UPDATE THESE
    cookies = {
        "_fbp": "fb.1.1652982905489.473636789",
        ".ASPXANONYMOUS": "7FPJC4O72AEkAAAANzJhYzQyZTAtMjBlMC00Y2U3LTg0NDgtNGNlYmQ5NzI2Y2Vj0",
        ".DOTNETNUKE": "2CBD48D7E6FEF2832140403BECBE9ECFC1100D5A638A241F9EA9A86E9614E9AD7D675F33B638CF6883EDE9CFD649CB12603BDF9491B5B18C1054918878F28B3B7B403EC45C6793BE92CA4683E005CD0E3B9F075FF0D874620916241664AA37D46DFA8E8D92D88C8E8CE48B8CEC6F3E7CF9D8691E89046D198866A11A08D306EA60C043AB",
        "dnn_IsMobile": "False",
        "language": "en-US",
        "_gid": "GA1.2.1856986867.1659476434",
        "_gat_gtag_UA_106589727_1": "1",
        "_ga": "GA1.1.1013963682.1652982905",
        "_ga_EXD94TY7GX": "GS1.1.1659476433.145.1.1659476490.0",
    }

    headers = {
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Connection": "keep-alive",
        # Requests sorts cookies= alphabetically
        # 'Cookie': '_fbp=fb.1.1652982905489.473636789; .ASPXANONYMOUS=7FPJC4O72AEkAAAANzJhYzQyZTAtMjBlMC00Y2U3LTg0NDgtNGNlYmQ5NzI2Y2Vj0; .DOTNETNUKE=2CBD48D7E6FEF2832140403BECBE9ECFC1100D5A638A241F9EA9A86E9614E9AD7D675F33B638CF6883EDE9CFD649CB12603BDF9491B5B18C1054918878F28B3B7B403EC45C6793BE92CA4683E005CD0E3B9F075FF0D874620916241664AA37D46DFA8E8D92D88C8E8CE48B8CEC6F3E7CF9D8691E89046D198866A11A08D306EA60C043AB; dnn_IsMobile=False; language=en-US; _gid=GA1.2.1856986867.1659476434; _gat_gtag_UA_106589727_1=1; _ga=GA1.1.1013963682.1652982905; _ga_EXD94TY7GX=GS1.1.1659476433.145.1.1659476490.0',
        "DNT": "1",
        "Referer": "https://www.linestarapp.com/Projections/Sport/MLB/Site/DraftKings/PID/1964",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
        "sec-ch-ua": '".Not/A)Brand";v="99", "Google Chrome";v="103", "Chromium";v="103"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"Windows"',
    }

    params = {
        "periodId": periodId,
        "site": "1",
        "sport": "3",
    }

    r = requests.get(
        "https://www.linestarapp.com/DesktopModules/DailyFantasyApi/API/Fantasy/GetSalariesV5",
        params=params,
        cookies=cookies,
        headers=headers,
    )
    r = r.json()
    # If there are no records, return None
    if len(r["Ownership"]["Salaries"]) == 0:
        raise ValueError(f"No data for periodId {periodId}")
    else:
        return r


def get_mlb_realized_slate(periodId):
    data = get_mlb_data(periodId)

    main_slate = [x for x in data["Ownership"]["Slates"] if x["SlateName"] == "Main"]
    # Raise errors if there are issues with selecting the right slate
    if len(main_slate) == 0:
        raise ValueError("No Main slate found")
    elif len(main_slate) > 1:
        raise ValueError("Multiple Main slates found")
    else:
        main_slate = main_slate[0]

    # Date of slate geames
    date = main_slate["SlateStart"][0:10]
    # Get SlateId for finding ownership data
    slate_id = [x["SlateId"] for x in main_slate["SlateGames"]][0]
    main_slate_game_ids = [x["GameId"] for x in main_slate["SlateGames"]]
    # Filter players to be those in games in the main slate, and have strictly positive projection
    slate_players = [
        x
        for x in data["Ownership"]["Salaries"]
        if (x["GID"] in main_slate_game_ids) & (x["PP"] > 0)
    ]

    # Make dictionary relating each player ID to projected ownership ammount
    player_ids = [x["PID"] for x in slate_players]
    proj_owned = {
        x["PlayerId"]: round(x["Owned"] / 100, 2)
        for x in data["Ownership"]["Projected"][str(slate_id)]
        if x["PlayerId"] in player_ids
    }
    # Get realized ownership for GPP tournaments that have contest type 4 on Linestar
    actual_owned = [
        x["OwnershipData"]
        for x in data["Ownership"]["ContestResults"]
        if (x["Contest"]["SlateId"] == slate_id) & (x["Contest"]["ContestType"] == 4)
    ][0]
    actual_owned = {
        x["PlayerId"]: round(x["Owned"] / 100, 2)
        for x in actual_owned
        if x["PlayerId"] in player_ids
    }

    # Adding batting order data
    for player in slate_players:
        # If player is pitcher, batting order is 0
        if player["POS"] in ["RP", "SP"]:
            player["BattingOrder"] = 0
        # Otherwise, alert numbers from player notes between 31 and 39
        # inclusive denote a players batting order
        else:
            found_order = False
            parsed_notes = json.loads(player["Notes"])
            for note in parsed_notes:
                if 31 <= note["Alert"] <= 39:
                    player["BattingOrder"] = note["Alert"] - 30
                    found_order = True
            # If there is not note for batting order, its NaN
            if not found_order:
                player["BattingOrder"] = None
        try:
            # Adding projected ownership
            player["ProjOwned"] = proj_owned[player["PID"]]
        except KeyError:
            player["ProjOwned"] = None

        try:
            # Adding realized ownership
            player["actual_owned"] = actual_owned[player["PID"]]
        except KeyError:
            player["actual_owned"] = None

    # Make dictionaries with data we need
    slate_players = [
        {
            "Name": x["Name"],
            "Position": x["POS"],
            "Salary": x["SAL"],
            "Game": x["GI"],
            "Team": x["PTEAM"],
            "Opponent": x["OTEAM"],
            "Order": x["BattingOrder"],
            "Projection": x["PP"],
            "Scored": x["PS"],
            "pOwn": x["ProjOwned"],
            "actOwn": x["actual_owned"],
        }
        for x in slate_players
    ]

    frame = pd.DataFrame(slate_players)
    # SP and RP can fill P position
    frame["Position"] = frame["Position"].replace({"SP": "P", "RP": "P"})
    # Assume players that can fill multiple positions can only fill the first one listed
    frame["Position"] = frame["Position"].str.split("/", expand=True)[0]
    # Extract Game string
    frame["Game"] = frame["Game"].str.split(" ", expand=True)[0]
    # Drop non-pitcher players with 0 batting order
    frame = frame.drop(frame[(frame["Position"] != "P") & (frame["Order"] == 0)].index)
    frame = frame.dropna()
    return (date, frame)


def get_mlb_proj_slate(periodId):
    data = get_mlb_data(periodId)

    main_slate = [x for x in data["Ownership"]["Slates"] if x["SlateName"] == "Main"]
    # Raise errors if there are issues with selecting the right slate
    if len(main_slate) == 0:
        raise ValueError("No Main slate found")
    elif len(main_slate) > 1:
        raise ValueError("Multiple Main slates found")
    else:
        main_slate = main_slate[0]

    # Date of slate geames
    date = main_slate["SlateStart"][0:10]
    # Get SlateId for finding ownership data
    slate_id = [x["SlateId"] for x in main_slate["SlateGames"]][0]
    main_slate_game_ids = [x["GameId"] for x in main_slate["SlateGames"]]
    # Filter players to be those in games in the main slate, and have >1
    # projected points.
    slate_players = [
        x
        for x in data["Ownership"]["Salaries"]
        if (x["GID"] in main_slate_game_ids) & (x["AggProj"] > 1)
    ]
    # Construct dictionary relating player IDs to projected ownership
    player_ids = [x["PID"] for x in slate_players]
    proj_owned = {
        x["PlayerId"]: round(x["Owned"] / 100, 2)
        for x in data["Ownership"]["Projected"][str(slate_id)]
        if x["PlayerId"] in player_ids
    }

    for player in slate_players:
        # Adding batting order data
        # If player is pitcher, batting order is 0
        if player["POS"] in ["RP", "SP"]:
            player["BattingOrder"] = 0
        # Otherwise, alert numbers from player notes between 31 and 39 inclusive
        # denote a players batting order
        else:
            found_order = False
            parsed_notes = json.loads(player["Notes"])
            for note in parsed_notes:
                if 31 <= note["Alert"] <= 39:
                    player["BattingOrder"] = note["Alert"] - 30
                    found_order = True
            # If there is not note for batting order, its 0
            if not found_order:
                player["BattingOrder"] = None
        try:
            # Adding projected ownership
            player["ProjOwned"] = proj_owned[player["PID"]]
        except KeyError:
            # If nothing found, assume 0
            player["ProjOwned"] = None

    # Make dictionaries with data we need
    slate_players = [
        {
            "Name": x["Name"],
            "Position": x["POS"],
            "Salary": x["SAL"],
            "Game": x["GI"],
            "Team": x["PTEAM"],
            "Opponent": x["OTEAM"],
            "Order": x["BattingOrder"],
            "Projection": x["AggProj"],
            "pOwn": x["ProjOwned"],
        }
        for x in slate_players
    ]

    frame = pd.DataFrame(slate_players)
    # SP and RP can fill P position
    frame["Position"] = frame["Position"].replace({"SP": "P", "RP": "P"})
    # Assume players that can fill multiple positions can only fill the first one listed
    frame["Position"] = frame["Position"].str.split("/", expand=True)[0]
    # Extract Game string
    frame["Game"] = frame["Game"].str.split(" ", expand=True)[0]
    # Drop non-pitcher players with 0 batting order
    frame = frame.drop(frame[(frame["Position"] != "P") & (frame["Order"] == 0)].index)
    frame = frame.dropna()
    return (date, frame)


def close_matches(x, possible):
    matches = get_close_matches(x, possible, cutoff=0.80)
    if matches:
        return matches[0]
    else:
        return np.nan


if __name__ == "__main__":
    periodId = int(input("Enter period ID to fetch projections for: "))
    # Get Linestar slate
    date, ls_slate = get_mlb_proj_slate(periodId)
    # Get DraftKings slate, merge it to the linestar slate so we can get DraftKings player IDs
    dk = pd.read_csv("./data/mlb_slates/DKSalaries.csv")
    dk["Name"] = dk["Name"].apply(lambda x: close_matches(x, ls_slate["Name"]))
    slate = ls_slate.merge(
        dk,
        left_on=["Name", "Salary", "Team"],
        right_on=["Name", "Salary", "TeamAbbrev"],
        how="left",
        suffixes=(None, "_r"),
    )
    # Somestimes multiple name matches are found, so merging causes duplicate rows
    slate = slate.drop_duplicates(subset=["Name", "Team"])
    slate = slate[
        [
            "Name",
            "ID",
            "Position",
            "Salary",
            "Game",
            "Team",
            "Opponent",
            "Order",
            "Projection",
            "pOwn",
        ]
    ]

    # Raise errors if there are data consistency issues
    if len(slate) > len(ls_slate):
        raise ValueError(
            "Merged slate is longer than Linestar slate. Possible issues with duplicate rows."
        )

    # Just drop any mysterious NA rows and hope for the best
    slate = slate.dropna()
    # Ensure batting order is integer
    slate["Order"] = slate["Order"].astype(int)
    slate.to_csv(f"./data/mlb_slates/{date}.csv", index=False)
    os.remove("./data/mlb_slates/DKSalaries.csv")
