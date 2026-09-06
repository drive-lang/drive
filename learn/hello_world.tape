Greet {
	subject,

	Self ( subject;
		self.subject = subject
	)

	greeting (;
		"Hello, `subject`!"
	)
}

Greet('Tape').greeting()
