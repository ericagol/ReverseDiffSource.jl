#########################################################################
#
#   Julia Package for reverse mode automated differentiation (from source)
#
#########################################################################

module ReverseDiffSource

  import Base.show

  # naming conventions
  const TEMP_NAME = "_tmp"   # prefix of new variables
  const DERIV_PREFIX = "d"   # prefix of gradient variables

  ## misc functions
  dprefix(v::Union(Symbol, String, Char)) = symbol("$DERIV_PREFIX$v")

  isSymbol(ex)   = isa(ex, Symbol)
  isDot(ex)      = isa(ex, Expr) && ex.head == :.   && isa(ex.args[1], Symbol)
  isRef(ex)      = isa(ex, Expr) && ex.head == :ref && isa(ex.args[1], Symbol)

  ## temp var name generator
  let
    vcount = Dict()
    global newvar
    function newvar(radix::Union(String, Symbol)=TEMP_NAME)
      vcount[radix] = haskey(vcount, radix) ? vcount[radix]+1 : 1
      return symbol("$(radix)$(vcount[radix])")
    end

    global resetvar
    function resetvar()
      vcount = Dict()
    end
  end

  #####  ExNode type  ######
  type ExNode{T}
    main
    parents::Vector
    val
  end

  ExNode(typ::Symbol, main)          = ExNode{typ}(main, ExNode[], NaN)
  ExNode(typ::Symbol, main, parents) = ExNode{typ}(main, parents,  NaN)

  typealias NConst     ExNode{:constant}
  typealias NExt       ExNode{:external}
  typealias NCall      ExNode{:call}
  typealias NComp      ExNode{:comp}
  typealias NRef       ExNode{:ref}
  typealias NDot       ExNode{:dot}
  typealias NSRef      ExNode{:subref}
  typealias NSDot      ExNode{:subdot}
  typealias NExt       ExNode{:external}
  typealias NAlloc     ExNode{:alloc}
  typealias NFor       ExNode{:for}
  typealias NIn        ExNode{:within}


  function show(io::IO, res::ExNode)
    pl = join( map(x->repr(x.main), res.parents) , " / ")
    # print(io, "[$(res.nodetype)] $(repr(res.name)) ($(res.value))")
    print(io, "[$(typeof(res))] $(repr(res.main)) ($(res.val))")
    length(pl) > 0 && print(io, ", from = $pl")
  end

  typealias ExNodes Vector{ExNode}

  #####  ExGraph type  ######
  type ExGraph
    nodes::ExNodes
    exitnodes::Dict
  end

  ExGraph() = ExGraph(ExNode[], Dict{Symbol, ExNode}())

  ######  Graph functions  ######
  function add_node(g::ExGraph, nargs...)
    v = ExNode(nargs...)
    push!(g.nodes, v)
    v
  end

  ancestors(n::ExNode) = union( Set(n), ancestors(n.parents) )
  ancestors(n::Vector) = union( map(ancestors, n)... )


  ##########  Parameterized type to ease AST exploration  ############
  type ExH{H}
    head::Symbol
    args::Vector
    typ::Any
  end
  toExH(ex::Expr) = ExH{ex.head}(ex.head, ex.args, ex.typ)
  toExpr(ex::ExH) = Expr(ex.head, ex.args...)

  typealias ExEqual    ExH{:(=)}
  typealias ExDColon   ExH{:(::)}
  typealias ExPEqual   ExH{:(+=)}
  typealias ExMEqual   ExH{:(-=)}
  typealias ExTEqual   ExH{:(*=)}
  typealias ExTrans    ExH{symbol("'")} 
  typealias ExCall     ExH{:call}
  typealias ExBlock    ExH{:block}
  typealias ExLine     ExH{:line}
  typealias ExVcat     ExH{:vcat}
  typealias ExFor      ExH{:for}
  typealias ExRef      ExH{:ref}
  typealias ExIf       ExH{:if}
  typealias ExComp     ExH{:comparison}
  typealias ExDot      ExH{:.}

  # variable symbol sampling functions
  getSymbols(ex::Any)    = Set{Symbol}()
  getSymbols(ex::Symbol) = Set{Symbol}(ex)
  getSymbols(ex::Array)  = mapreduce(getSymbols, union, ex)
  getSymbols(ex::Expr)   = getSymbols(toExH(ex))
  getSymbols(ex::ExH)    = mapreduce(getSymbols, union, ex.args)
  getSymbols(ex::ExCall) = mapreduce(getSymbols, union, ex.args[2:end])  # skip function name
  getSymbols(ex::ExRef)  = setdiff(mapreduce(getSymbols, union, ex.args), Set(:(:), symbol("end")) )# ':'' and 'end' do not count
  getSymbols(ex::ExDot)  = Set{Symbol}(ex.args[1])  # return variable, not fields
  getSymbols(ex::ExComp) = setdiff(mapreduce(getSymbols, union, ex.args), 
    Set(:(>), :(<), :(>=), :(<=), :(.>), :(.<), :(.<=), :(.>=), :(==)) )

  ## variable symbol substitution functions
  substSymbols(ex::Any, smap::Dict)     = ex
  substSymbols(ex::Expr, smap::Dict)    = substSymbols(toExH(ex), smap::Dict)
  substSymbols(ex::Vector, smap::Dict)  = map(e -> substSymbols(e, smap), ex)
  substSymbols(ex::ExH, smap::Dict)     = Expr(ex.head, map(e -> substSymbols(e, smap), ex.args)...)
  substSymbols(ex::ExCall, smap::Dict)  = Expr(:call, ex.args[1], map(e -> substSymbols(e, smap), ex.args[2:end])...)
  substSymbols(ex::ExDot, smap::Dict)   = (ex = toExpr(ex) ; ex.args[1] = substSymbols(ex.args[1], smap) ; ex)
  substSymbols(ex::Symbol, smap::Dict)  = get(smap, ex, ex)




  ######  Includes  ######
  include("graph_funcs.jl")
  include("graph_code.jl")
  include("reversegraph.jl")
  include("deriv_rules.jl")
  include("reversediff.jl")


  ######  Exports  ######
  export 
    reversediff, ndiff,
    @deriv_rule, deriv_rule, 
    @type_decl, type_decl


end # module ReverseDiffSource

