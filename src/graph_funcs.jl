#########################################################################
#
#    Misc graph manipulation functions
#
#########################################################################

######## transforms n-ary +, *, max, min, sum, etc...  into binary ops  ###### 
function splitnary!(g::ExGraph)
	for n in g.nodes
	    if isa(n, NCall) &&
	        in(n.main, [:+, :*, :sum, :min, :max]) && 
	        (length(n.parents) > 2 )

	        nn = add_node(g, NCall( n.main, n.parents[2:end] ) )
	        n.parents = [n.parents[1], nn]  
	    
	    elseif isa(n, NFor)
	    	splitnary!(n.main[2])

	    end
	end
end

####### fuses nodes nr and nk  ########
# removes node nr and keeps node nk 
#  updates parent links to nr, and references in exitnodes
function fusenodes(g::ExGraph, nk::ExNode, nr::ExNode)

	# replace references to nr by nk in parents of other nodes
    for n in filter(n -> !is(n,nr) & !is(n,nk), g.nodes)
    	for i in 1:length(n.parents)
    		is(n.parents[i], nr) && (n.parents[i] = nk)
    	end
    end

	# replace references to nr in exitnodes dictionnary
    for (k,v) in g.exitnodes
        is(v, nr) && (g.exitnodes[k] = nk)
    end

	# replace references to nr in subgraphs (for loops)
    for n in filter(n -> isa(n, NFor), g.nodes)
    	mp = n.main[3]
    	for (k,v) in mp
    		is(v, nr) && (mp[k] = nk)
    	end
    end

    # remove node nr in g
    filter!(n -> !is(n,nr), g.nodes)
end

####### evaluate operators on constants  ###########
function evalconstants!(g::ExGraph, emod = Main)
	i = 1 
	while i < length(g.nodes) 
	    n = g.nodes[i]

	    restart = false
		if isa(n, NCall) & 
			all( map(n->isa(n, NConst), n.parents) ) &
			!in(n.main, [:zeros, :ones, :vcat])

			# calculate value
			res = invoke(emod.eval(n.main), 
	            tuple([ typeof(x.main) for x in n.parents]...),
	            [ x.main for x in n.parents]...)

			# create a new constant node and replace n with it
			nn = add_node(g, NConst(res) )
			fusenodes(g, nn, n) 

            restart = true  
        end

	    i = restart ? 1 : (i + 1)
	end

	# separate pass on subgraphs
	map( n -> evalconstants!(n.main[2]), filter(n->isa(n, NFor), g.nodes))
end

####### trims the graph to necessary nodes for exitnodes to evaluate  ###########
function prune!(g::ExGraph)
	g2 = ancestors(collect(values(g.exitnodes)))
	filter!(n -> in(n, g2), g.nodes)

	# separate pass on subgraphs
	map( n -> prune!(n.main[2]), filter(n->isa(n, NFor), g.nodes))
end

####### sort graph to an evaluable order ###########
function evalsort!(g::ExGraph)
	g2 = ExNode[]

	while length(g2) < length(g.nodes)
		canary = length(g2)
		nl = setdiff(g.nodes, g2)
	    for n in nl
	        if !any( [ in(x, nl) for x in n.parents] ) # | (length(n.parents) == 0)
	            push!(g2,n)
	        end
	    end
	    (canary == length(g2)) && error("[evalsort!] probable cycle in graph")
	end

	g.nodes = g2
end

####### calculate the value of each node  ###########
function calc!(g::ExGraph; params=Dict(), emod = Main)

	function evaluate(n::Union(NAlloc, NCall))
		invoke(emod.eval(n.main), 
	           tuple([ typeof(x.val) for x in n.parents]...),
	           [ x.val for x in n.parents]...)
	end 

	evaluate(n::NExt) = get(params, n.main, emod.eval(n.main))
    # TODO : catch error if undefined
	evaluate(n::NConst) = emod.eval(n.main)
	evaluate(n::NRef)   = emod.eval( Expr(:ref, n.parents[1].val, n.main...) )
	evaluate(n::NDot)   = emod.eval( Expr(:., n.parents[1].val, n.main) )
	evaluate(n::NSRef)  = n.parents[1].val
	evaluate(n::NSDot)  = n.parents[1].val
	evaluate(n::NFor)   = (calc!(n.main[2]) ; nothing)
	evaluate(n::NIn)    = nothing

	evalsort!(g)
	for n in g.nodes
		n.val = evaluate(n)
	end
end

###### inserts graph src into dest  ######
function add_graph!(src::ExGraph, dest::ExGraph, smap::Dict)
    evalsort!(src)
    nmap = Dict()
    for n in src.nodes  #  n = src[1]  
        if !isa(n, NExt)
        	nn = copy(n) # node of same type
        	nn.parents = [ nmap[n2] for n2 in n.parents ]
        	push!(dest.nodes, nn)
            # nn = add_node(dest, n.nodetype, n.main, 
            # 				[ nmap[n2] for n2 in n.parents ])
            nmap[n] = nn

        else
            if haskey(smap, n.main)
                nmap[n] = smap[n.main]
            else

            	nn = copy(n)
	        	push!(dest.nodes, nn)
	            # nn = add_node(dest, n.nodetype, n.main, [])
	            nmap[n] = nn

                warn("unmapped symbol in source graph $(n.main)")
            end
        end
    end

    nmap
end


###### plots graph using GraphViz
function plot(g::ExGraph)

	gshow(n::NConst) = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"square\", style=filled, fillcolor=\"lightgreen\"];"
	gshow(n::NExt)   = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"circle\", style=filled, fillcolor=\"orange\"];"
	gshow(n::NCall)  = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"box\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NComp)  = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"box\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NRef)   = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"rarrow\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NDot)   = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"rarrow\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NSRef)  = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"larrow\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NSDot)  = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"larrow\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NAlloc) = 
		"$(nn[n]) [label=\"$(n.main)\", shape=\"parallelogram\", style=filled, fillcolor=\"lightblue\"];"
	gshow(n::NIn)    = 
		"$(nn[n]) [label=\"in\", shape=\"box3d\", style=filled, fillcolor=\"pink\"];"

	nn = Dict() # node names for GraphViz
	i = 1
	out = ""
	for n in g.nodes
		if isa(n, NFor)  # FIXME : will fail for nested for loops
			nn[n] = "cluster_$i"
			i += 1
			out = out * """
	    		subgraph $(nn[n]) { label=\"for $(n.main[1])\" ; 
					color=pink;
				"""

			for n2 in filter(n -> !isa(n, NExt), n.main[2].nodes)
			    nn[n2] = "n$i"
				i += 1
				out = out * gshow(n2)
			end

			out = out * "};"
		else
			nn[n] = "n$i"
			i += 1
			out = out * gshow(n)
		end	
	end

	for n in g.nodes 
		if isa(n, NFor)  # FIXME : will fail for nested for loops
			g2 = n.main[2]
			for n2 in filter(n -> !isa(n, NExt), g2.nodes)
			    for p in n2.parents
			    	if in(p, keys(g2.inmap))
			        	out = out * "$(nn[g2.inmap[p]]) -> $(nn[n2]) [style=dotted];"
			    	else
			    		out = out * "$(nn[p]) -> $(nn[n2]);"
			        end
			    end
			end
		else
		    for p in n.parents
		        out = out * "$(nn[p]) -> $(nn[n]);"
		    end
		end	
	end

	for (el, en) in g.setmap
	    out = out * "n$el [label=\"$el\", shape=\"note\", stype=filled, fillcolor=\"lightgrey\"];"
	    out = out * "$(nn[en]) -> n$el [ style=dotted];"
	end

	Graph("digraph gp {layout=dot; labeldistance=5; scale=0.5 ; $out }")
end