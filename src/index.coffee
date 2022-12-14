import * as Fn from "@dashkite/joy/function"
import * as Text from "@dashkite/joy/text"
import * as API from "@dashkite/sky-api-description"
import * as Sublime from "@dashkite/maeve/sublime"
import { Accept, MediaType } from "@dashkite/media-type"

describe = Fn.tee ( context ) ->
  { request } = context
  if ( api = await API.Description.discover request )?
    if request.target == "/"
      context.response =
        description: "ok"
        content: api.data 
    else
      context.api = api
  else
    context.response =
      description: "not found"

resource = Fn.tee ( context ) ->
  { request, api } = context
  if request.resource?
    context.resource = api.resources[ request.resource.name ]
    # add target and url if we don't already have one
    request.target ?= context.resource.encode request.resource.bindings
    request.url ?= "https://#{ request.domain }/#{ request.target }"
  else if ( resource = api.decode request )?
    request.resource = resource
    context.resource = api.resources[ resource.name ]
  else
    context.response = description: "not found"

options = Fn.tee ( context ) ->
  { request, resource } = context
  if request.method == "options"
    # TODO do we need to avoid sending the CORS header
    #      if it isn't a CORS request?
    context.response =
      description: "no content"
      headers:
        "access-control-allow-methods": [ resource.options ]

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
  if ( candidates = Sublime.Request.Headers.get "accept" )?
    if ( targets = method.response[ "content-type" ] )?
      if ( accept = Accept.selectAll candiates, targets )?
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
      Sublime.Response.headers.set response, "content-type",
        type = Accept.selectFromContent response.content, accept
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
  context.request.authorization = do ->
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
  { accepts, request } = context
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
  context.response

classifier = ( handler ) ->
  process = run [
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
