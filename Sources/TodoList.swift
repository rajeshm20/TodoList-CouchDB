/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Foundation

import LoggerAPI
import TodoListAPI
import SwiftyJSON

import CouchDB


#if os(Linux)
    typealias Valuetype = Any
#else
    typealias Valuetype = AnyObject
#endif


/// TodoList for CouchDB
public class TodoList: TodoListAPI {

    static let defaultCouchHost = "127.0.0.1"
    static let defaultCouchPort = UInt16(5984)
    static let defaultDatabaseName = "todolist"

    let databaseName = "todolist"

    let designName = "TodoList-CouchDB"

    let connectionProperties: ConnectionProperties

    public init(_ dbConfiguration: DatabaseConfiguration) {

        connectionProperties = ConnectionProperties(host: dbConfiguration.host!,
                                                    port: Int16(dbConfiguration.port!),
                                                    secured: true,
                                                    username: dbConfiguration.username,
                                                    password: dbConfiguration.password)

    }

    public init(database: String = TodoList.defaultDatabaseName,
                host: String = TodoList.defaultCouchHost,
                port: UInt16 = TodoList.defaultCouchPort,
                username: String? = nil, password: String? = nil) {


        connectionProperties = ConnectionProperties(host: host, port: Int16(port), secured: false,
                                                    username: username, password: password)

    }

    public func count(withUserID: String? = nil, oncompletion: (Int?, ErrorProtocol?) -> Void) {

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        let userParameter = withUserID == nil ? "default" : withUserID!

        database.queryByView("user_todos", ofDesign: designName,
                             usingParameters: [.keys([userParameter])]) {
                                document, error in

                                if let document = document where error == nil {

                                    if let numberOfTodos = document["rows"][0]["value"].int {
                                        oncompletion( numberOfTodos, nil)
                                    } else {
                                        oncompletion( 0, nil)
                                    }

                                } else {
                                    oncompletion(nil, error)
                                }
        }
    }

    public func clear(withUserID: String? = nil, oncompletion: (ErrorProtocol?) -> Void) {

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        let userParameter = withUserID == nil ? "default" : withUserID!

        database.queryByView("user_todos", ofDesign: designName,
                             usingParameters: [.descending(true), .includeDocs(true),
                                               .keys([userParameter])]) {
                                                document, error in

                                                guard let document = document else {
                                                    oncompletion(error)
                                                    return
                                                }


                                                guard let idRevs = try? parseGetIDandRev(document) else {
                                                    oncompletion(error)
                                                    return
                                                }

                                                let count = idRevs.count

                                                if count == 0 {
                                                    oncompletion( nil )
                                                } else {
                                                    var numberCompleted = 0

                                                    for i in 0...count-1 {
                                                        let item = idRevs[i]

                                                        database.delete(item.0, rev: item.1) {
                                                            error in

                                                            if error != nil {
                                                                oncompletion(error)
                                                                return
                                                            }

                                                            numberCompleted += 1

                                                            if numberCompleted == count {
                                                                oncompletion( nil )
                                                            }

                                                        }

                                                    }
                                                }
        }
    }

    public func clearAll(oncompletion: (ErrorProtocol?) -> Void) {

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        database.queryByView("all_todos", ofDesign: designName,
                             usingParameters: [.descending(true), .includeDocs(true)]) {
                                document, error in

                                guard let document = document else {
                                    oncompletion(error)
                                    return
                                }


                                guard let idRevs = try? parseGetIDandRev(document) else {
                                    oncompletion(error)
                                    return
                                }

                                let count = idRevs.count

                                if count == 0 {
                                    oncompletion(nil)
                                } else {
                                    var numberCompleted = 0

                                    for i in 0...count-1 {
                                        let item = idRevs[i]

                                        database.delete(item.0, rev: item.1) {
                                            error in

                                            if error != nil {
                                                oncompletion(error)
                                                return
                                            }

                                            numberCompleted += 1

                                            if numberCompleted == count {
                                                oncompletion(nil)
                                            }

                                        }

                                    }
                                }
        }
    }

    public func get(withUserID: String?, oncompletion: ([TodoItem]?, ErrorProtocol?) -> Void ) {

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        let userParameter = withUserID == nil ? "default" : withUserID!

        database.queryByView("user_todos", ofDesign: designName,
                             usingParameters: [.descending(true), .includeDocs(true),
                                               .keys([userParameter])]) {
                                                document, error in

                                                if let document = document where error == nil {

                                                    do {
                                                        let todoItems = try parseTodoItemList(document)
                                                        oncompletion(todoItems, nil)
                                                    } catch {
                                                        oncompletion(nil, error)

                                                    }

                                                } else {
                                                    oncompletion(nil, error)
                                                }


        }

    }

    public func get(withUserID: String?, withDocumentID: String,
                    oncompletion: (TodoItem?, ErrorProtocol?) -> Void ) {

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        let withUserID = withUserID == nil ? "default" : withUserID!

        database.retrieve(withDocumentID) {
            document, error in


            if let document = document {
                let documentID = document["_id"].string
                let userID = document["user"].string
                let title = document["title"].string
                let order = document["order"].int
                let completed = document["completed"].bool

                if withUserID == userID {
                    guard let sdocumentID = documentID else {
                        oncompletion(nil, error)
                        return
                    }

                    guard let suserID = userID else {
                        oncompletion(nil, error)
                        return
                    }

                    guard let stitle = title else {
                        oncompletion(nil, error)
                        return
                    }

                    guard let sorder = order else {
                        oncompletion(nil, error)
                        return
                    }

                    guard let scompleted = completed else {
                        oncompletion(nil, error)
                        return
                    }

                    let todoItem = TodoItem(documentID: sdocumentID, userID: suserID, order: sorder,
                                            title: stitle, completed: scompleted)

                    oncompletion(todoItem, nil)
                } else {
                    oncompletion(nil, TodoCollectionError.AuthError)
                }

            } else {
                oncompletion(nil, error)
            }



        }

    }

    public func add(userID: String?, title: String, order: Int = 0, completed: Bool = false,
                    oncompletion: (TodoItem?, ErrorProtocol?) -> Void ) {

        let userID = userID == nil ? "default" : userID!

        let json: [String: Valuetype] = [
            "type": "todo",
            "user": userID,
            "title": title,
            "order": order,
            "completed": completed
        ]

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)


        database.create(JSON(json)) {
            id, rev, document, error in

            if let id = id {
                let todoItem = TodoItem(documentID: id, userID: userID, order: order,
                                        title: title, completed: completed)

                oncompletion( todoItem, nil)
            } else {
                oncompletion(nil, error)
            }

        }


    }

    public func update(documentID: String, userID: String?, title: String?,
                       order: Int?, completed: Bool?, oncompletion: (TodoItem?, ErrorProtocol?) -> Void ) {


        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        let userID = userID == nil ? "default" : userID

        database.retrieve(documentID) {
            document, error in
            if let document = document, userID = userID {
                if userID == document["user"].string {

                    let rev = document["_rev"].string!

                    let json: [String: Valuetype] = [
                        "type": "todo",
                        "user": userID,
                        "title": title != nil ? title! :
                            document["title"].string!,
                        "order": order != nil ? order! :
                            document["order"].int!,
                        "completed": completed != nil ? completed! :
                            document["completed"].bool!
                    ]

                    database.update(documentID, rev: rev, document: JSON(json)) {
                        rev, document, error in

                        if error != nil {

                            oncompletion(nil, error)
                        } else {
                            self.get(withUserID: userID, withDocumentID: documentID) {
                                document, error in
                                if let document = document {
                                    oncompletion(document, nil)
                                } else {
                                    oncompletion(nil, error)
                                }
                            }
                        }
                    }
                } else {
                    oncompletion(nil, error)
                }
            } else {
                oncompletion(nil, TodoCollectionError.AuthError)
            }
        }

    }

    public func delete(withUserID: String?, withDocumentID: String, oncompletion: (ErrorProtocol?) -> Void) {

        let couchDBClient = CouchDBClient(connectionProperties: connectionProperties)
        let database = couchDBClient.database(databaseName)

        let withUserID = withUserID == nil ? "default" : withUserID

        database.retrieve(withDocumentID) {
            document, error in

            if let document = document {

                let rev = document["_rev"].string!
                let user = document["user"].string!

                if withUserID == user {
                    database.delete( withDocumentID, rev: rev) {
                        error in

                        oncompletion(nil)
                    }
                }

            } else {
                oncompletion(error)
            }
        }


    }


}


func parseGetIDandRev(_ document: JSON) throws -> [(String, String)] {
    guard let rows = document["rows"].array else {
        throw TodoCollectionError.ParseError
    }

    return rows.flatMap {

        let doc = $0["doc"]
        let id = doc["_id"].string!
        let rev = doc["_rev"].string!

        return (id, rev)

    }

}

func parseTodoItemList(_ document: JSON) throws -> [TodoItem] {
    guard let rows = document["rows"].array else {
        throw TodoCollectionError.ParseError
    }

    let todos: [TodoItem] = rows.flatMap {

        let doc = $0["value"]

        let id = doc[0].string
        let user = doc[1].string
        let title = doc[2].string
        let completed = doc[3].bool
        let order = doc[4].int


        return TodoItem(documentID: id!, userID: user!, order: order!, title: title!, completed: completed!)

    }

    return todos
}
