handlers =
  foo:
    post: -> 
      description: "ok"
      content: "success!"
    delete: ->
      description: "no content"
  bar:
    get: ->
      content: greeting: "hello, world!"

export default handlers