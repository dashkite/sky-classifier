import * as Fn from "@dashkite/joy/function"
import * as Val from "@dashkite/joy/value"
import * as Text from "@dashkite/joy/text"
import * as API from "@dashkite/sky-api-description"
import * as Sublime from "@dashkite/maeve/sublime"
import { Accept, MediaType } from "@dashkite/media-type"
import description from "./helpers/description"

lambdas = {}
stack = []

url = ( domain, target ) ->
  "https://#{ domain }#{ target }"

matchRequest = ( request ) ->
  ( prevRequest ) ->
    ( prevRequest.domain == request.domain ) && 
      ( Val.equal prevRequest.resource, request.resource ) &&
        ( prevRequest.method == request.method )

checkStack = Fn.tee ( context ) ->
  { request } = context
  if ( stack.find matchRequest request )?
    console.warn "sky-classifier: request matches 
      existing request", request
    context.response = description: "internal server error"

# TODO may want to check for empty host header?
ping = Fn.tee ( context ) ->
  { request } = context
  if request.target == "/ping"
    context.response = description: "ok"

lambda = Fn.tee ( context ) ->
  { request } = context
  if ( lambda = lambdas[ request.domain ] )?
    request.lambda = lambda
  else
    console.warn "sky-classifier: no matching lambda for 
      domain [ #{ request.domain } ]"
    context.response = description: "internal server error"

push = Fn.tee ( context ) ->
  { request } = context
  stack.push request

describe = Fn.tee ( context ) ->
  { request } = context
  if request.resource?.name == "description"
    context.resource = API.Resource.from { 
      name: "description"
      resource: description
    }   
    request.target ?= context.resource.encode request.resource.bindings
    request.url ?= url request.domain, request.target
  else
    console.log "sky-classifier: attempting discovery for", request
    response = await Sky.fetch {
      domain: request.domain
      lambda: request.lambda
      resource: { name: "description" }
      method: "get"
      headers: accept: [ "application/json" ]
    }
    context._api = response
    if response.description == "ok"
      api = API.Description.from JSON.parse response.content
      context.api = api
    else
      context.response = description: "not found"

resource = Fn.tee ( context ) ->
  { request, api } = context
  if !context.resource?
    if request.resource?
      context.resource = api.resources[ request.resource.name ]
      # add target and url if we don't already have one
      request.target ?= context.resource.encode request.resource.bindings
      request.url ?= url request.domain, request.target
    else if ( resource = api.decode request )?
      request.resource = resource
      context.resource = api.resources[ resource.name ]
    else
      context.response = description: "not found"
  if request.resource?.name == "description" && context._api?
    context.response = context._api

options = Fn.tee ( context ) ->
  { request, resource } = context
  if request.method == "options"
    console.log "OPTIONS REQUEST", request
    # TODO do we need to avoid sending the CORS header
    #      if it isn't a CORS request?
    context.response =
      description: "no content"
      headers:
        "access-control-allow-methods": [ "*" ]
        "access-control-allow-origin": [ request.headers.origin[0] ]
        "access-control-allow-credentials": [ true ]
        "access-control-expose-headers": [ "*" ]
        "acess-control-max-age": [ 7200 ]
        "access-control-allow-headers": [ "*" ]

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
      headers:
        allow: [ resources.options ]

acceptable = Fn.tee ( context ) ->
  { request, method } = context
  if ( candidates = Sublime.Request.Headers.get request, "accept" )?
    if ( targets = method.response[ "content-type" ] )?
      if ( accept = Accept.selectAll candidates, targets )?
        context.accept = accept
      else
        context.response =
          description: "not acceptable"
    else
      context.accept = candidates

supported = Fn.tee ( context ) ->
  { request, method } = context
  if request.content?
    if ( candidates = method.request?[ "content-type" ] )?
      if ( target = Sublime.Request.Headers.get request, "content-type" )?
        if ( type = Accept.select candidates, target )?
          category = MediaType.category type
        else
          context.response =
            description: "unsupported media type"
      else # malformed request, no content-type
        context.response =
          description: "bad request"
    category ?= MediaType.infer request.content
    switch category
      when "json"
        request.content = JSON.parse request.content
      # TODO decode binary encodings?
  else if method.request?[ "content-type" ]?
    context.response =
      description: "bad request"

accept = do ({ accept } = {}) ->
  ( context ) ->
    { accept, response } = context
    if response.content? && accept?
      type = Accept.selectByContent response.content, accept
      Sublime.Response.Headers.set response, "content-type", MediaType.format type
      if type?    
        switch MediaType.category type
          when "json" 
            response.content = JSON.stringify response.content
          # TODO possibly attempt to encode binary formats
      else
        context.response =
          description: "unsupported media type"

authorization = Fn.tee ( context ) ->
  { request } = context
  context.request.authorization ?= do ->
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
  { request } = context
  context.response = await handler request
  accept context
  if context.head
    # let Sublime take care of the rest
    context.response.description = "no content"

normalize = ( handler ) ->
  ( request ) -> Sublime.response await handler request

run = Fn.curry ( processors, context ) ->
  for processor in processors
    context = await processor context
    break if context.response?
  stack.pop()
  context.response

classifier = ( context, handler ) ->
  lambdas = context.lambdas
  process = run [
    checkStack
    ping
    lambda
    push
    describe
    resource
    options
    head
    method
    acceptable
    supported
    authorization
    invoke handler
  ]
  normalize ( request ) -> process { request }

export { classifier }
