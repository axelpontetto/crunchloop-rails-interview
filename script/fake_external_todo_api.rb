#!/usr/bin/env ruby
# frozen_string_literal: true

# A tiny in-memory stand-in for the external Todo API, so you can run the sync
# POC without the real service. NOT for production — no persistence, no auth.
#
#   ruby script/fake_external_todo_api.rb            # listens on :3001
#   EXTERNAL_TODO_API_URL=http://localhost:3001 bin/rails sync:run
#
# Implements the endpoints from docs/external-api.yaml:
#   GET    /todolists                                       - list all todolists (with nested items)
#   POST   /todolists                                       - create a todolist (with nested items)
#   PATCH  /todolists/{todolistId}                          - update a todolist's name
#   DELETE /todolists/{todolistId}                          - delete a todolist (and its items)
#   PATCH  /todolists/{todolistId}/todoitems/{todoitemId}   - update a todoitem
#   DELETE /todolists/{todolistId}/todoitems/{todoitemId}   - delete a todoitem
require "webrick"
require "json"

STORE = { lists: {}, seq: 0 }
def next_id = "ext-#{STORE[:seq] += 1}"

class TodosServlet < WEBrick::HTTPServlet::AbstractServlet
  def service(req, res)
    res["Content-Type"] = "application/json"
    parts = req.path.split("/").reject(&:empty?) # ["todolists", id, "todoitems", item_id]
    body = req.body.to_s.empty? ? {} : JSON.parse(req.body)

    case [req.request_method, parts.length]
    when ["GET", 1] # GET /todolists
      res.body = STORE[:lists].values.to_json
    when ["POST", 1] # POST /todolists
      list = build_list(body)
      STORE[:lists][list["id"]] = list
      res.status = 201
      res.body = list.to_json
    when ["PATCH", 2] # PATCH /todolists/{todolistId}
      list = STORE[:lists].fetch(parts[1])
      list["name"] = body["name"]
      list["updated_at"] = now
      res.body = list.to_json
    when ["DELETE", 2] # DELETE /todolists/{todolistId}
      STORE[:lists].delete(parts[1])
      res.status = 204
    when ["PATCH", 4] # PATCH /todolists/{todolistId}/todoitems/{todoitemId}
      item = STORE[:lists].fetch(parts[1])["items"].find { |i| i["id"] == parts[3] }
      item.merge!("description" => body["description"], "completed" => body["completed"], "updated_at" => now)
      res.body = item.to_json
    when ["DELETE", 4] # DELETE /todolists/{todolistId}/todoitems/{todoitemId}
      STORE[:lists].fetch(parts[1])["items"].reject! { |i| i["id"] == parts[3] }
      res.status = 204
    else
      res.status = 404
      res.body = "{}"
    end
  rescue KeyError
    res.status = 404
    res.body = "{}"
  end

  private

  def now = Time.now.utc.iso8601

  def build_list(body)
    items = Array(body["items"]).map do |i|
      { "id" => next_id, "source_id" => i["source_id"], "description" => i["description"],
        "completed" => i["completed"], "updated_at" => now }
    end
    { "id" => next_id, "source_id" => body["source_id"], "name" => body["name"],
      "updated_at" => now, "items" => items }
  end
end

port = Integer(ENV.fetch("PORT", 3001))
server = WEBrick::HTTPServer.new(Port: port, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
server.mount "/todolists", TodosServlet
trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
puts "Fake external Todo API listening on http://localhost:#{port}"
server.start
