Greet {
	subject,

	Self ( subject;
		self.subject = subject
	)

	greeting (;
		"Hello, `subject`!"
	)
}

@puts Greet('Drive').greeting()
