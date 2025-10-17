// Drink protocol

public protocol Drink: Equatable { 
    var mL: Int { get }
    var refillCost: Int { get }
    var cost: Int { get }
}