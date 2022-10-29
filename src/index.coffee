import * as Fn from "@dashkite/joy/function"
import * as Text from "@dashkite/joy/text"
import * as API from "@dashkite/sky-api-description"
import * as Sublime from "@dashkite/maeve/sublime"

describe = Fn.tee ( context ) ->
  { request } = context
  api = await API.Description.discover request
  if request.target == "/"
    context.response =
      description: "ok"
      content: api.data 
  else
    context.api = api

resource = Fn.tee ( context ) ->
  { request, api } = context
  if ( resource = api.decode request )?
    request.resource = resource
    context.resource = api.resources[ resource.name ]
  else
    context.response = description: "not found"

options = Fn.tee ( context ) ->
  { request, resource } = context
  if request.method == "options"
    context.response =
      description: "no content"
      headers:
        allow: [ resource.options ]

head = Fn.tee ( context ) ->
  { request } = context
  context.head = if request.method == "head"
    request.method = "get"
    true
  else false

method = Fn.tee ( context ) ->
  { request, resource } = context
  if ( method = resource.methods[ request.method ])?
    context.method = method
  else
    context.response =
      description: "method not allowed"

acceptable = Fn.tee ( context ) ->
  # TODO handle response content negotiation here
  # { request, method } = context
  # if ( accepts = method.accept request )?
  #   context.accepts = accepts
  # else
  #   context.response =
  #     description: "not acceptable"

supported = Fn.tee ( context ) ->
  # TODO handle request content negotiation here
  # { request, method } = context
  # if ( content = method.content request )?
  #   context.content = content
  # else
  #   context.response =
  #     description: "unsupported media type"
  context.content = context.request.content

lambda = Fn.curry Fn.rtee ( lambdas, context ) ->
  { request } = context
  if ( lambda = lambdas[ request.domain ] )?
    context.lambda = lambda
  else
    console.warn "sky-classifier: no matching lambda for 
      domain [ #{ request.domain } ]"
    context.response =
      description: "internal server error"

accept = ( accepts, response ) ->
  # TODO convert response based on acceptable context property
  response

authorization = Fn.tee ( context ) ->
  { request } = context
  context.authorization = do ->
    if ( header = Sublime.Request.Headers.get request, "authorization" )?
      [ credential, parameters... ] = Text.split ",", Text.trim header
      [ scheme, credential ] = Text.split /\s+/, credential
      parameters = parameters
        .map (parameter) -> Text.split "=", parameter
        .map ([ key, value ]) -> 
          [ Text.trim key ]: Text.trim value
        .reduce (( result, value ) -> Object.assign result, value ), {}
      { scheme, credential, parameters }
    else {}

invoke = Fn.curry Fn.rtee ( handler, context ) ->
  { accepts, request, content, lambda } = context
  context.response = accept accepts,
    await handler {
      request...
      content
      lambda
    }
  if context.head
    # let Sublime take care of the rest
    context.response.description = "no content"

normalize = ( handler ) ->
  ( request ) -> Sublime.response await handler request

run = Fn.curry ( processors, context ) ->
  for processor in processors
    context = await processor context
    break if context.response?
  context.response

classifier = ( lambdas, handler ) ->
  process = run [
    describe
    resource
    options
    head
    method
    acceptable
    supported
    lambda lambdas
    authorization
    invoke handler
  ]
  normalize ( request ) -> process { request }

export default classifier
