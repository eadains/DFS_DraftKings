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
    (1, 4000.0),
    (2, 1500.0),
    (3, 1000.0),
    (4, 750.0),
    (5, 500.0),
    (6, 250.0),
    (7, 200.0),
    (9, 150.0),
    (11, 100.0),
    (16, 75.0),
    (21, 60.0),
    (31, 50.0),
    (41, 40.0),
    (51, 30.0),
    (66, 25.0),
    (86, 20.0),
    (111, 15.0),
    (141, 10.0),
    (186, 8.0),
    (241, 6.0),
    (316, 5),
    (436, 4.0),
    (691, 3.0),
    (1331, 2.0),
    (3046, 1.5),
    (6616, 1.0),
    (19976, 0.0)
]
println("Making optim data")
# SET PARAMETER: Overlap, total entries, and samples
data = PGATournyOptimData(slate, payoffs, 4, 95100, 250)
# SET PARAMETER: number of lineups to generate
println("Getting lineups")
lineups = tourny_lineups(data, 50)
println("Writing lineups")
write_lineups(slate, lineups)