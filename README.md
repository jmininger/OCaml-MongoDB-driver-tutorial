# MongoML tutorial: An OCaml driver for MongoDB

### Introduction
[MongoML][1] is currently the only OCaml driver for MongoDB. It uses 
[BSON](http://bsonspec.org/) to communicate via tcp/ip sockets to the MongoDB 
server. This means that it relies on OCaml's built-in [_Unix module_](https://caml.inria.fr/pub/docs/manual-ocaml/libref/Unix.html)
(although most of the Unix api seems to work on Windows, according to the docs).  

#### Async vs Sync API
Commands in the _Mongo_ API are synchronous, but there is a Mongo\_lwt package
inside of module in the [MongoML Repo][2] that wraps all _Mongo_ functions
in a Lwt monad. This module does not appear to come in the opam package.  
  
####APIs
Here is the documentation for the three APIs that we will be using:
  - [Mongo](http://massd.github.io/mongo/doc/Mongo.html)
  - [MongoAdmin](http://massd.github.io/mongo/doc/MongoAdmin.html)
  - [Bson](http://massd.github.io/bson/doc/Bson.html)

Its a pretty small api, and the Bson functions are particularly worth looking
at.  


### Installation
MongoML does not work on ocaml versions > than 4.05.0, so the best solution is
to create an opam switch.

```
$ mkdir MongoTutorial
$ cd MongoTutorial
$ opam switch create Mongo ocaml.4.05.0
$ opam install mongo
```

Now, any opam commands in the directory (and all directories lower in the
hierarchy) will be using the switch environment instead of the default opam
environment. 

Make sure that a mongod instance is running: 
```
$ mongod
```

**One more thing**: I strongly reccomend downloading 
[MongoCompass](https://docs.mongodb.com/compass/master/install/), a Desktop UI
that allows you to see the changes that you make to your MongoDB.

### Basic functions
Lets begin by creating a collection. In MongoDB, _collections_ are the NoSQL
analogs of SQL tables, and _documents_ are SQL row analogs.  

```ocaml
(* val create : string -> int -> string -> string -> t *)

let myMongoDB = 
  let open Mongo in
  let url = "127.0.0.1" in (* string *)
  let port = 27017 in (* int *)
  let dbName = "TutorialDB" in
  let collectionName = "newCollection" in
  try 
    create url port dbName collectionName
  with 
    Mongo_failed ex -> Pervasives.print_endline ex
```

Here the _create_ function connects to the db and creates a `Mongo.t` which 
points to the collection and is needed as an argument for almost
every other function in the API.  

If the `TutorialDB` database already exists, you will receieve a pointer to
that database--there is no error to indicate that the db already exists (the
same goes for the collection argument)

Also in this function is the `Mongo.Mongo_failed` exception type that contains
a string. This is the only exception in the Mongo module, and many functions
raise it if an error occurs. 

```ocaml
let () = 
  destory myMongoDB (* spelled "de-story" not "destroy" *)
```
After use, a `Mongo.t` should be destroyed to preserve resources.  

**Important:** the spelling is **correct** in the code sample above. It is an unfortunate
spelling error that the current MongoML repo has corrected, but that correction
is lacking the version that opam distributes. It has been
like this for at least two years. If the opam version is ever upgraded, it will
likely cause breaking changes.   

### Inserting Elements

```ocaml
type person = { name: string; age: int; hobbies: string list }

let person_to_bson {name; age; hobbies} = 
  let hobby_elems = List.map (Bson.create_string) hobbies in
  Bson.empty 
    |> Bson.add_element "name" (Bson.create_string name)
    |> Bson.add_element "age" (Bson.create_int64 (Int64.of_int age))
    |> Bson.add_element "hobbies" (Bson.create_list hobby_elems)

let bson_to_person bson = 
  let name = 
    Bson.get_element "name" bson
      |> Bson.get_string in
  let age = 
     Bson.get_element "age" bson
      |> Bson.get_int64 
      |> Int64.to_int in
  let hobbies =
    Bson.get_element "hobbies" bson
      |> Bson.get_list 
      |> List.map (Bson.get_string) in
  {name; age; hobbies }

(** Main: Insert 5 documents into mongodb and print any exceptions that are thrown)
let () =
  let people = [
        {name="John Doe"; age=21; hobbies=["Soccer"; "Coding"]};
        {name="Jane Smith"; age=25; hobbies=["Drawing"]};
        {name="Person1"; age=10; hobbies=["philosophy"; "reading"]};
        {name="Person2"; age=20; hobbies=["surfing"; "volleyball"]};
        {name="Person3"; age=30; hobbies=["coding"]}
      ] 
  in 
  try 
      (* val insert : t -> Bson.t list -> unit *)
    List.map person_to_bson people
      |> Mongo.insert myMongoDB

  with 
    Mongo.Mongo_failed ex -> (
      Pervasives.print_endline ex;
      Mongo.destory myMongoDB
  )
```

To create Bson objects, we start with an empty objects and add key value pairs,
using the `Bson.add_element` function. 

### BSON   

The following is all available Bson constructors: 
```ocaml
val create_double : float -> element
val create_string : string -> element
val create_doc_element : t -> element
val create_list : element list -> element
val create_user_binary : string -> element
val create_objectId : string -> element
val create_boolean : bool -> element
val create_utc : int64 -> element
val create_null : unit -> element
val create_regex : string -> string -> element
val create_jscode : string -> element
val create_jscode_w_s : string -> t -> element
val create_int32 : int32 -> element
val create_int64 : int64 -> element
val create_minkey : unit -> element
val create_maxkey : unit -> element
```
Each function above has a corresponding *get* function (ex. string: `get_string`, list: `get_list`) 
that takes a BSON element and returns an OCaml type.   

Also important are the `get_element`, `add_element`, and `remove_element` functions that provide 
operations for interacting with `Bson.t` types.   

Here are their signatures: 
```ocaml
val add_element : string -> Bson.element -> Bson.t -> Bson.t

val get_element : string -> Bson.t -> Bson.element

val remove_element : string -> Bson.t -> Bson.t
```
   

### Query Objects and Selector Objects

Queries in MongoDB are specified using BSON objects called _query objects_.
We can make a query object that grabs all documents from our database with an
`age >= 21` or with `name = "Person1"` like this:
```ocaml
let query = 
  Bson.empty
    |> Bson.add_element "$or" 
      (Bson.empty
        |> Bson.add_element "age" 
            (Bson.create_doc_element 
              (Bson.add_element "$gte" 
              (Bson.create_int64 (Int64.of_int 21)) Bson.empty))
        |> Bson.add_element "name" 
          (Bson.create_doc_element 
            (Bson.add_element "$eq" 
            (Bson.create_string "Person1") Bson.empty))
      )
```

We can also make sure that only certain columns from documents are returned by
using a _selector object_.  

```ocaml
let selector = Bson.empty
  |> Bson.add_element "name" (Bson.create_boolean true)
  |> Bson.add_element "age" (Bson.create_boolean true)
```

If passed as an argument with the query object above, we get the NoSQL equivalent
of: 
```sql
SELECT name, age, _id
FROM myMongoDB
WHERE age >= 21 or name = "Person1"
```

### Queries and MongoReply

Each query returns a MongoReply, which consists of a header, flags, num_items_returned, 
a cursor_id, and a document list. To see what a MongoReply looks like use `MongoReply.to_string` 
to return a printable string.
We can use `MongoReply.get_document_list` to get a list of documents that are returned.    


**Note:** In the MongoML api, only functions ending with *"of_num"* return cursors


```ocaml
(* Get all documents *)
let all_docs = 
  Mongo.find myMongoDB 
    |> MongoReply.get_document_list

(* Get first doc *)
let first_doc = 
  Mongo.find_one myMongoDB 
    |> MongoReply.get_document_list

(* Get docs matching the query *)
let matching_docs = 
  Mongo.find_q query_obj
    |> MongoReply.get_document_list

(* Get docs matching the query, with only the specified attributes *)
let matching_docs = 
  Mongo.find_q_s query_obj selector_obj
    |> MongoReply.get_document_list
```
Note: I forego the obligatory `try-with` blocks in the above examples  

There are some more subtle variations of the above query funcs that can be found 
[here](http://massd.github.io/mongo/doc/Mongo.html)  

### Cursors
A cursor_id acts like an iterator, holding a reference to a particular spot in the 
collection. In the MongoML api, only functions ending with *"of_num"* return cursors.

```ocaml
(* Get the first two docs *)
let reply = Mongo.find_of_num myMongoDB 2 in
let cursor = MongoReply.get_cursor reply in

(* Get the next doc *)
let newReply = Mongo.get_more_of_num cursor 1
let next_cursor = MongoReply.get_cursor newReply

(* Get the rest of the documents *)
let rest = Mongo.get_more next_cursor
...

Mongo.kill_cursors myMongoDB [cursor; next_cursor]
```  
The  `kill_cursors` method is meant to help MongoDB save resources when your are done with 
the cursors.   

**Note:** the specific case for `Mongo.find_of_num someDB 1`, where 1 is the integer passed
in, does not return a cursor, like one might expect.

### Deleting Entries
```ocaml
 val delete_one : t -> Bson.t -> unit

 val delete_all : t -> Bson.t -> unit
```
```ocaml
(* Selects docs with: name == "John Doe" *)
let delete_selector = 
  Bson.empty
  |>  Bson.add_element "name" 
    (Bson.create_doc_element 
      (Bson.empty 
        |> Bson.add_element "$eq" (Bson.create_string "John Doe"))
    )

let _ = 
  delete_one myMongoDB delete_selector

(* Selects docs with names containing "Person" *)
let people_prefix_selector = 
  Bson.empty 
  |> Bson.add_element "name" (Bson.create_doc_element (
      Bson.empty 
      |> Bson.add_element "$regex" (Bson.create_string "Person")
    ))

let _ = 
  Mongo.delete_all myMongoDB people_prefix_selector

(* 
  To delete all the elements in a collection without a selector, 
   pass in an empty Bson object: 
*)
let _  = 
  Mongo.delete_all myMongoDB (Bson.empty)

```
### Updates and Update Objects

Updates work pretty much the same as queries and deletes, with the exception that updates
take an additional object that describe how to update documents matching the selection object.

```ocaml
val update_one : t -> Bson.t * Bson.t -> unit

val update_all : t -> Bson.t * Bson.t -> unit
```
Each of the functions above take a pair of BSON values, the first representing 
the selector document, the second, representing the update document

```ocaml
(* Take a name, and increase the age by one in all documents with a matching name *)
let birthday name =
  let select_doc = 
    Bson.empty |> 
      Bson.add_element "name" (Bson.create_doc_element (
        Bson.empty |> Bson.add_element "$eq" (Bson.create_string name))) in
  let update_doc = 
    Bson.empty |> Bson.add_element "$inc" (Bson.create_int64 1) in
  Bson.update_all myMongoDB (select_doc, update_doc)
```


### The MongoAdmin Module
MongoAdmin provides a set of useful tools for managing a db cluster.  

The MongoAdmin module does not require that you specify a DB and Collection to 
create an object --only a port and a uri.

See the [API](http://massd.github.io/mongo/doc/MongoAdmin.html) for more information
```ocaml
val create : string -> int -> t

val destory : t -> unit


val listDatabases : t -> MongoReply.t
val buildInfo : t -> MongoReply.t
val collStats : t -> MongoReply.t
val connPoolStats : t -> MongoReply.t
val cursorInfo : t -> MongoReply.t
val getCmdLineOpts : t -> MongoReply.t
val hostInfo : t -> MongoReply.t
val listCommands : t -> MongoReply.t
val serverStatus : t -> MongoReply.t
```  

### Potential Projects
  - Create ppx syntax extensions to convert records to bson and vice versa
  - Create a query-object builder function
  - Figure out how to hack the MongoML project to add other mongo ops like authentication
  - Figure out how to use the Lwt module of the library


[1]:http://massd.github.io/mongo/
[2]:https://github.com/MassD/mongo
