Person {
    Self.count := 0

    new (;
        Self.count += 1
    )
}

Person()
Person()
Person().count == 3
