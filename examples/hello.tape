Greet {
	subject,

	new ( subject;
		self.subject = subject
	)

	greeting (;
		"Hello, `subject`!"
	)
}

Greet('Lost').greeting()
