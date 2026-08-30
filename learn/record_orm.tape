### Introduction

`Table` (`lost/table.tape`) is an ActiveRecord-style ORM. It sits on top of `lost/database.tape`. Read learn/database.tape first if `Sqlite` and `@connect` are new to you.

CRUD works through one instance. Take a schema Struct. Call `db.find_or_create_table(Schema)` on it. This single call returns one ready `Table` instance. The instance is already wired to the database and the schema. This method needs no separate composition step. It needs no static `Self.database` declaration. Every method below (`all`, `find`, `create`, and more) runs directly on this instance.
###
@load 'lost/database.tape'
@load 'lost/table.tape'

db := @connect Sqlite(':memory:')

Survivor <
	id: Primary_Key
	name: String
	status: String
>

survivors := db.find_or_create_table(Survivor)


### create

`create` takes a Struct of the columns to insert. It does not take a Dictionary. `create` returns the created record as a Struct. The `id` field fills in automatically.
###
jack   := survivors.create(<name := 'Jack', status := 'rescued'>)
kate   := survivors.create(<name := 'Kate', status := 'rescued'>)
sawyer := survivors.create(<name := 'Sawyer', status := 'missing'>)

@assert jack.id == 1, 'create should assign an id automatically'
@assert jack.name == 'Jack', 'create should return the created record'


### all

`all` fetches every row as an Array of Structs. Each Struct matches the table's own schema.
###
@assert survivors.all().length() == 3, 'all should fetch every row'


### find and find_by

`find` looks up one row by id. `find_by` takes a Struct of conditions. It returns the first matching row. It returns nil when nothing matches.
###
@assert survivors.find(jack.id).name == 'Jack', 'find should look up a row by id'
@assert survivors.find_by(<name := 'Kate'>).id == kate.id, 'find_by should return the first row matching the conditions'
@assert survivors.find_by(<name := 'nobody'>) == nil, 'find_by should return nil when nothing matches'


### where

`where` works like `find_by`. But it returns every matching row as an Array. It does not return only the first row.
###
rescued := survivors.where(<status := 'rescued'>)
@assert rescued.length() == 2, 'where should return every matching row'


### update and delete

`update` takes an id and a Struct of the columns to change. `delete` removes one row by id.
###
survivors.update(jack.id, <name := 'Jack Shephard'>)
@assert survivors.find(jack.id).name == 'Jack Shephard', 'update should change the row in place'

survivors.delete(sawyer.id)
@assert survivors.all().length() == 2, 'delete should remove the row'
