// Breakfast struct
import Drink
import PBJ
import BananaPudding

public struct Breakfast { 
    public var drink: any Drink
    public var food: PBJ
    public var dessert: BananaPudding
    
    public init(drink: any Drink, food: PBJ, dessert: BananaPudding) { 
        self.drink = drink
        self.food = food
        self.dessert = dessert
    }
}