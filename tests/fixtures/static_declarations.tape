Person {
    Self.count := 0

    Self (;
        Self.count += 1
    )
}

Person()
Person()
Person().count == 3
