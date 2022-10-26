import * as Fn from "@dashkite/joy/function"
import * as API from "@dashkite/sky-api-description"
import * as Sublime from "@dashkite/maeve/sublime"

describe = Fn.tee ( context ) ->
  if request.target == "/"
    context.response =
      description: "ok"
      content: context.api 
  else
    context.api = API.Description.make description

resource = Fn.tee ( context ) ->
  { request } = context
  if ( resource = description.decode request.target )?
    request.resource = resource
  else
    context.response = description: "not found"

options = Fn.tee ( context ) ->
  if request.method == "options"
    context.response =
      description: "no content"
      headers:
        allow: [ description.options ]

head = ( context ) ->
  { request } = context
  context.head = if request.method == "head"
    request.method = "get"
    true
  else false

method = ( context ) ->
  { request } = context
  { resource } = request
  if ( method = description.getMethod resource.name, request.method )?
    context.method = method
  else
    context.response =
      description: "method not allowed"

acceptable = ( context ) ->
  { request, method } = context
  if ( accepts = method.accept request )?
    context.accepts = accepts
  else
    context.response =
      description: "not acceptable"

supported = ( context ) ->
  { request, method } = context
  if ( content = method.content request )?
    context.content = content
  else
    context.response =
      description: "unsupported media type"

lambda = ( context ) ->
  { request, domains } = context
  if ( lambda = domains[ request.domain ] )?
    context.lambda = lambda
  else
    console.warn "sky-classifier: no matching lambda for 
      domain [ #{ request.domain } ]"
    context.response =
      description: "internal server error"

accept = ( response ) ->
  # TODO convert response
  response

invoke = ( context ) ->
  { accepts, handler, request, content, lambda } = context
  context.response = accept accepts,
    await handler {
      request...
      resource
      content
      lambda
    }
  if context.head
    # let Sublime take care of the rest
    context.response.description = "no content"

normalize = ( handler ) ->
  ( request ) -> 
    Sublime.Response.normalize await handler request

run = Fn.curry ( processors, context ) ->
  for processor in processors
    context = await processor context
    break if context.response?
  context.response

classifier = normalize run [
  describe
  resource
  options
  head
  method
  acceptable
  supported
  lambda
  invoke
]

export default classify
