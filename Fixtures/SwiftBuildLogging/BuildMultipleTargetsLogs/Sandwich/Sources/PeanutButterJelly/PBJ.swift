// PBJ struct

public struct PBJ { 
    public let peanutButter: Bool
    public let jelly: Bool
    public let jellyKind: Jelly?

    public init(peanutButter: Bool, jellyKind: Jelly? = nil) { 
        self.peanutButter = peanutButter
        self.jelly = jellyKind != nil
        self.jellyKind = jellyKind
    }
}

public enum Jelly {
    case grape
    case strawberry
    case cherry
}