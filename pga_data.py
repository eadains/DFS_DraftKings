import pandas as pd
import numpy as np
import requests
from difflib import get_close_matches
import os
from config import cookies, headers


def get_pga_data(periodId):
    params = {
        "periodId": periodId,
        "site": "1",
        "sport": "5",
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


def get_pga_realized_slate(periodId):
    data = get_pga_data(periodId)

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
    slate_id = main_slate["Id"]
    # Filter players to be those that have strictly positive projection
    slate_players = [x for x in data["Ownership"]["Salaries"] if x["PP"] > 0]

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
        try:
            # Adding projected ownership
            player["ProjOwned"] = proj_owned[player["PID"]]
        except KeyError:
            player["ProjOwned"] = 0.0

        try:
            # Adding realized ownership
            player["actual_owned"] = actual_owned[player["PID"]]
        except KeyError:
            player["actual_owned"] = 0.0

    # Make dictionaries with data we need
    slate_players = [
        {
            "Name": x["Name"],
            "Salary": x["SAL"],
            "Projection": x["PP"],
            "Scored": x["PS"],
            "pOwn": x["ProjOwned"],
            "actOwn": x["actual_owned"],
        }
        for x in slate_players
    ]

    frame = pd.DataFrame(slate_players)
    return (date, frame)


def get_pga_proj_slate(periodId):
    data = get_pga_data(periodId)

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
    # Construct dictionary relating player IDs to projected ownership
    player_ids = [x["PID"] for x in slate_players]
    proj_owned = {
        x["PlayerId"]: round(x["Owned"] / 100, 2)
        for x in data["Ownership"]["Projected"][str(slate_id)]
        if x["PlayerId"] in player_ids
    }

    for player in slate_players:
        try:
            # Adding projected ownership
            player["ProjOwned"] = proj_owned[player["PID"]]
        except KeyError:
            # If nothing found, assume NaN
            player["ProjOwned"] = 0.0

    # Make dictionaries with data we need
    slate_players = [
        {
            "Name": x["Name"],
            "Salary": x["SAL"],
            "Projection": x["AggProj"],
            "pOwn": x["ProjOwned"],
        }
        for x in slate_players
    ]

    frame = pd.DataFrame(slate_players)
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
    date, ls_slate = get_pga_proj_slate(periodId)
    # Get DraftKings slate, merge it to the linestar slate so we can get DraftKings player IDs
    dk = pd.read_csv("./data/pga_slates/DKSalaries.csv")
    dk["Name"] = dk["Name"].apply(lambda x: close_matches(x, ls_slate["Name"]))
    slate = ls_slate.merge(
        dk,
        left_on=["Name", "Salary"],
        right_on=["Name", "Salary"],
        how="left",
        suffixes=(None, "_r"),
    )
    # Sometimes multiple name matches are found, so merging causes duplicate rows
    slate = slate.drop_duplicates(subset=["Name"])
    slate = slate[["Name", "ID", "Salary", "Projection", "pOwn"]]

    # Raise errors if there are data consistency issues
    if len(slate) > len(ls_slate):
        raise ValueError(
            "Merged slate is longer than Linestar slate. Possible issues with duplicate rows."
        )

    # Just drop any mysterious NA rows and hope for the best
    slate = slate.dropna()
    slate.to_csv(f"./data/pga_slates/{date}.csv", index=False)
    os.remove("./data/pga_slates/DKSalaries.csv")
