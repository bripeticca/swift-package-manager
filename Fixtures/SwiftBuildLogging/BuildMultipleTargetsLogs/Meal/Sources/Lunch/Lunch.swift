// This is my lunch.
import ChocolateCake
import SugarCookie
import Drink
import BLT

public struct Lunch { 
    var drink: any Drink
    var food: BLT
    var dessert: LunchDessert
    
    public func orderDessert(_ kind: LunchDessert) { 
        switch kind { 
            case .cake:
            let cake = ChocolateCake()
            print("My cake has \(cake.sugar)g of sugar!")
            case .cookie:
            let cookie = SugarCookie()
            print("My cookie has \(cookie.sugar)g of sugar")
            break
        }
    }

    public init(drink: any Drink, food: BLT, dessert: LunchDessert) { 
        self.drink = drink
        self.food = food
        self.dessert = dessert
    }
}

public enum LunchDessert { 
    case cake
    case cookie
}