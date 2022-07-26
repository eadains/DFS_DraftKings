using Dates
include("optim.jl")
include("types.jl")
include("io.jl")
include("opp_teams.jl")

# SET PARAMETER: slate date
println("Getting slate")
slate = get_pga_slate("2022-07-28")
# SET PARAMETER: payoffs
payoffs = Tuple{Int64,Float64}[
    (1, 1500.0),
    (2, 750.0),
    (3, 300.0),
    (4, 150.0),
    (5, 100.0),
    (6, 75.0),
    (7, 60.0),
    (9, 50.0),
    (11, 40.0),
    (15, 30.0),
    (20, 25.0),
    (26, 20.0),
    (36, 15.0),
    (46, 10.0),
    (61, 8.0),
    (81, 6.0),
    (106, 5.0),
    (161, 4.0),
    (276, 3.0),
    (551, 2.0),
    (1266, 1.50),
    (2716, 1.0),
    (8186, 0.0)
]
println("Making optim data")
# SET PARAMETER: Overlap, total entries, and samples
data = PGATournyOptimData(slate, payoffs, 3, 35600, 250)
# SET PARAMETER: number of lineups to generate
println("Getting lineups")
lineups = tourny_lineups(data, 50)
println("Writing lineups")
write_lineups(slate, lineups)