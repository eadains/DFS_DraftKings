using Dates
include("optim.jl")
include("types.jl")
include("io.jl")
include("opp_teams.jl")


"""
    solve_cash()

Solves cash optimization and writes results to file
"""
function solve_cash()
    slate = get_mlb_slate("$(Dates.today())")
    points, lineup = do_optim(slate)
    lineup = transform_lineup(slate, lineup)
    write_lineup(points, lineup)
end


"""
    solve_tourny()

Solves tournament optimization and writes results to file
"""
function solve_tourny()
    slate = get_mlb_slate("$(Dates.today())")
    payoffs = Tuple{Int64,Float64}[
        (1, 150.0),
        (2, 100.0),
        (3, 60.0),
        (4, 45.0),
        (5, 35.0),
        (6, 25.0),
        (7, 20.0),
        (9, 15.0),
        (11, 10.0),
        (14, 8.0),
        (17, 6.0),
        (21, 5.0),
        (26, 4.0),
        (36, 3.0),
        (56, 2.0),
        (121, 1.50),
        (256, 1.00),
        (611, 0.75),
        (1491, 0.50),
        (3420, 0)
    ]
    data = MLBTournyOptimData(slate, payoffs, 7, 14200, 100)

    num = 0
    while true
        print("Enter number of tournament lineups to generate: ")
        num = readline()
        try
            num = parse(Int, num)
            break
        catch
            print("Invalid number entered, try again\n")
        end
    end
    lineups = tourny_lineups(data, num)
    lineups = [transform_lineup(slate, lineup) for lineup in lineups]
    write_lineups(lineups)
end