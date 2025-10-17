// Juice struct
import Drink

public struct Juice: Drink { 
    public let mL: Int = 100
    public let refillCost: Int = 2
    public let cost: Int = 3
    public var kind: JuiceKind

    public init(_ kind: JuiceKind) { 
        self.kind = kind
    }
}

public enum JuiceKind { 
    case apple
    case mango
    case peach
    case pineapple
}