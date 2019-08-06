module GraphUtils
    class IncidenceList
        def initialize (@nvertices : Int32)
            @edges = Array(Array(Int32)).new(@nvertices) { Array(Int32).new }
        end

        def add_edge! (from : Int32, to : Int32)
            @edges[from] << to
        end

        def nvertices
            return @nvertices
        end

        def edges_from (v : Int32)
            return @edges[v]
        end
    end

    def self.invert_graph (g)
        res = IncidenceList.new(g.nvertices)
        (0...g.nvertices).each do |i|
            g.edges_from(i).each do |j|
                res.add_edge!(j, i)
            end
        end
        return res
    end

    class BfsTree
        def initialize (@nvertices : Int32, source : Int32)
            @parents = Array(Int32).new(@nvertices, -1)
            @dist = Array(Int32).new(@nvertices, -1)
            @dist[source] = 0
        end

        def distance_known? (v : Int32)
            return @dist[v] != -1
        end

        def has_parent? (v : Int32)
            return @parents[v] != -1
        end

        def set_parent! (child : Int32, parent : Int32)
            @parents[child] = parent
            @dist[child] = @dist[parent] + 1
            self
        end

        def nvertices
            return @nvertices
        end

        def parent_of (v : Int32)
            return @parents[v]
        end

        def distance_to (v : Int32)
            return @dist[v]
        end
    end

    class FastQueue(T)
        def initialize (prealloc : Int = 0)
            @queue = Array(T).new(prealloc)
            @queue_start = 0
        end

        def empty?
            return @queue_start == @queue.size
        end

        def push (elem)
            @queue << elem
            self
        end

        def shift
            res = @queue[@queue_start]
            @queue_start += 1
            return res
        end
    end

    def self.build_bfs_tree (g, source : Int32)
        tree = BfsTree.new(g.nvertices, source)

        queue = FastQueue(Int32).new(g.nvertices)
        queue.push(source)
        until queue.empty?
            v = queue.shift
            g.edges_from(v).each do |w|
                unless tree.distance_known?(w)
                    tree.set_parent!(child: w, parent: v)
                    queue.push(w)
                end
            end
        end

        return tree
    end

    def self.tree_lca (tree, a : Int32, b : Int32, j : Int32) : {Int32, Bool}
        j_on_path = false
        while true
            j_on_path ||= (a == j || b == j)
            case tree.distance_to(a) <=> tree.distance_to(b)
            when .> 0
                a = tree.parent_of(a)
            when .< 0
                b = tree.parent_of(b)
            else
                break
            end
        end

        while a != b
            j_on_path ||= (a == j || b == j)
            a = tree.parent_of(a)
            b = tree.parent_of(b)
        end

        j_on_path ||= a == j
        return {a, j_on_path}
    end
end
