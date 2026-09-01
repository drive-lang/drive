Date {
	year: Int
	month: Int
	day: Int
	weekday: Int   # 0 = Sunday .. 6 = Saturday

	Self.today (; @ruby )
	Self.parse ( string; @ruby )

	iso8601 (; @ruby )
	to_s (; @ruby )
}
