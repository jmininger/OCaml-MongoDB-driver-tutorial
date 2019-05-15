(*********************** Data and utility funcs ************************)

type person = { name: string; age: int; hobbies: string list }

let person_to_str {name; age; hobbies } =
  let hobby_str = String.concat ", " hobbies in
  Printf.sprintf "Name: %s, age: %d, hobbies: %s" name age hobby_str

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

(*********************** Creating a db instance ************************)

(* Global Database Instance *)
(* val myMongoDB : Mongo.t *)
let myMongoDB = 
  let open Mongo in
  let url = "127.0.0.1" in (* string *)
  let port = 27017 in (* int *)
  let dbName = "TutorialDB" in
  let collectionName = "newCollection" in
  create url port dbName collectionName

(*********************** Inserting ************************)

(** val insert_users : unit -> unit *)
let insert_users () =
  let people = [
        {name="John Doe"; age=21; hobbies=["Soccer"; "Coding"]};
        {name="Jane Smith"; age=25; hobbies=["Drawing"]};
        {name="Person1"; age=10; hobbies=["philosophy"; "reading"]};
        {name="Person2"; age=20; hobbies=["surfing"; "volleyball"]};
        {name="Person3"; age=30; hobbies=["coding"]}
      ] 
  in 
  try 
    List.map person_to_bson people
      |> Mongo.insert myMongoDB

  with 
    Mongo.Mongo_failed ex -> (
      Pervasives.print_endline ex;
      Mongo.destory myMongoDB
  )

(*********************** Querying ************************)

(* SELECT * FROM myMongoDB WHERE age >= 21 *)
(* { "age": {"$gte": 21 }} *)
(** val query_obj : Bson.t *)
let query_obj = 
  Bson.empty
    |> Bson.add_element "age" 
      (Bson.create_doc_element
        (Bson.add_element "$gte" 
          (Bson.create_int64 (Int64.of_int 21)) Bson.empty))


(* SELECT age, name *)
(** val selector_obj : Bson.t *)
let selector_obj = 
  Bson.empty 
    |> Bson.add_element "name" (Bson.create_boolean true)
    |> Bson.add_element "age" (Bson.create_boolean true)


(* SELECT * FROM myMongoDB WHERE age >= 21 *)
(** val query1 : unit -> Bson.t list *)
let query1 () = 
  Mongo.find_q myMongoDB query_obj
    |> MongoReply.get_document_list 

(* SELECT name, age FROM myMongoDB WHERE age >= 21 *)
let query2 () = 
  Mongo.find_q_s myMongoDB query_obj selector_obj
    |> MongoReply.get_document_list

(*********************** Main ************************)

let () = 
  insert_users ();

  (* Print documents matching the query *)
  query1 ()
    |> List.map bson_to_person
    |> List.map person_to_str
    |> List.iter print_endline;

  query2 ()
    |> List.map Bson.to_simple_json
    |> List.iter print_endline;
  
  
  (* Delete all elements in the database *)  
  Mongo.delete_all myMongoDB Bson.empty;
  Mongo.destory myMongoDB