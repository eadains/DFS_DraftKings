using Dates
include("optim.jl")
include("types.jl")
include("io.jl")

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

    overlap = 0
    while true
        print("Enter overlap parameter: ")
        overlap = readline()
        try
            overlap = parse(Int, overlap)
            break
        catch
            print("Invalid number entered, try again\n")
        end
    end

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
    lineups = tourny_lineups(slate, num, overlap)
    lineups = [transform_lineup(slate, lineup) for lineup in lineups]
    write_lineups(lineups)
end
