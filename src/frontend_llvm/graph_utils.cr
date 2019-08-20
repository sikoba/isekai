module Isekai::LLVMFrontend::GraphUtils

class IncidenceList
    def initialize (@nvertices : Int32)
        @edges = Array(Array(Int32)).new(nvertices) { Array(Int32).new }
    end

    def add_edge! (from : Int32, to : Int32)
        @edges[from] << to
    end

    def nvertices
        return @nvertices
    end

    def edges_from (vertex : Int32)
        return @edges[vertex]
    end
end

def self.invert_graph (graph)
    res = IncidenceList.new(nvertices: graph.nvertices)
    (0...graph.nvertices).each do |i|
        graph.edges_from(i).each do |j|
            res.add_edge!(j, i)
        end
    end
    return res
end

class BfsTree
    def initialize (@nvertices : Int32, from source : Int32)
        @parents = Array(Int32).new(nvertices, -1)
        @dist = Array(Int32).new(nvertices, -1)
        @dist[source] = 0
    end

    def distance_known? (to vertex : Int32)
        @dist[vertex] != -1
    end

    def has_parent? (vertex : Int32)
        @parents[vertex] != -1
    end

    def set_parent! (child : Int32, parent : Int32)
        @parents[child] = parent
        @dist[child] = @dist[parent] + 1
        self
    end

    def nvertices
        @nvertices
    end

    def parent_of (vertex : Int32)
        @parents[vertex]
    end

    def distance (to vertex : Int32)
        @dist[vertex]
    end
end

private class FastQueue(T)
    def initialize (initial_capacity : Int = 0)
        @queue = Array(T).new(initial_capacity: initial_capacity)
        @queue_start = 0
    end

    def empty?
        @queue_start == @queue.size
    end

    def push (x)
        @queue << x
        self
    end

    def shift
        res = @queue[@queue_start]
        @queue_start += 1
        return res
    end
end

def self.build_bfs_tree (on graph, from source : Int32)
    tree = BfsTree.new(nvertices: graph.nvertices, from: source)

    queue = FastQueue(Int32).new(initial_capacity: graph.nvertices)
    queue.push(source)
    until queue.empty?
        v = queue.shift
        graph.edges_from(v).each do |w|
            unless tree.distance_known?(to: w)
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
        case tree.distance(to: a) <=> tree.distance(to: b)
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
