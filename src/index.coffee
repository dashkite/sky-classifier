import * as Fn from "@dashkite/joy/function"
import * as Val from "@dashkite/joy/value"
import * as Text from "@dashkite/joy/text"
import * as Type from "@dashkite/joy/type"
import * as API from "@dashkite/sky-api-description"
import * as Sublime from "@dashkite/maeve/sublime"
import { Accept, MediaType } from "@dashkite/media-type"
import { Authorization, Link } from "@dashkite/http-headers"
import { Name } from "@dashkite/name"
import description from "./helpers/description"
import { JSON64 } from "./helpers/utils"
import JSONValidator from "ajv/dist/2020"
import addFormats from "ajv-formats"
import { html as descriptionHTML } from "@dashkite/api-documentation-generator"

parseDomain = ( domain ) ->
  mode = process.env.mode ? "development"
  [ name, namespace, tld ] = domain.split "."
  if mode != "production"
    [ components..., address ] = name.split "-"
    name = components.join "-"
  { name, namespace, tld }

env = JSON.parse process.env.context

Normalize =

  location: Fn.tee ( response ) ->
    if ( values = response.headers.location )?
      response.headers.location = values.map ( value ) ->
        if Type.isObject value
          API.Resource
            .from value
            .encode()
        else value
      
  link: Fn.tee ( response ) ->
    if ( values = response.headers.link )?
      response.headers.link = values.map ( value ) ->
        if Type.isObject value
          { url, resource, parameters } = value
          url ?= API.Resource
            .from resource
            .encode()
          Link.format { url, parameters }
        else value

  date: Fn.tee ( response ) ->
    if ( values = response.headers.data )?
      response.headers.data = do ->
        for value in values
          if !( Type.isDate value )
            Response.Headers.set response, "date",
              value.toUTCString()
          else value

  "last-modified": Fn.tee ( response ) ->
    if ( values = response.headers.data )?
      response.headers.data = do ->
        for value in values
          if !( Type.isDate value )
            Response.Headers.set response, "last-modified",
              value.toUTCString()
          else value

Normalize.links = Fn.tee Fn.pipe [
  Normalize.location
  Normalize.link
]

Normalize.dates = Fn.tee Fn.pipe [
  Normalize.date
  Normalize[ "last-modified" ]
]

normalize = Fn.tee Fn.pipe [
  Normalize.links
  Normalize.dates
]

validator = new JSONValidator allowUnionTypes: true
addFormats validator

url = ( domain, target ) ->
  "https://#{ domain }#{ target }"

matchRequest = ( request ) ->
  ( prevRequest ) ->
    ( prevRequest.domain == request.domain ) && 
      ( Val.equal prevRequest.resource, request.resource ) &&
        ( prevRequest.method == request.method )

checkStack = ( context, stack ) ->
  { request } = context
  !( stack.find matchRequest request )?

# TODO may want to check for empty host header?
ping = Fn.tee ( context ) ->
  { request } = context
  if request.target == "/ping"
    context.response = description: "ok"

lambda = Fn.tee ( context ) ->
  { request } = context
  { namespace, name } = parseDomain request.domain
  uri = Name.getURI { type: "lambda", namespace, name }
  if ( lambda = env[ uri ] )?
    request.lambda = lambda
  else
    console.warn "sky-classifier: no matching lambda for 
      domain [ #{ request.domain } ]"
    context.response = description: "internal server error"

describe = Fn.tee ( context ) ->
  # console.log "sky-classifier: describe"
  { request } = context
  if request.target == "/" || request.resource?.name == "description"
    context.resource = API.Resource.from { 
      name: "description"
      resource: description
    }
    request.target ?= "/"
    request.url ?= url request.domain, request.target
    request.resource ?= { name: "description" }
  else
    # console.log "sky-classifier: attempting discovery for", request
    response = await Sky.fetch {
      domain: request.domain
      lambda: request.lambda
      resource: { name: "description" }
      method: "get"
      headers: accept: [ "application/json" ]
    }
    if response.description == "ok"
      # console.log "sky-classifier: adding description to context"
      context.api = API.Description.from JSON.parse response.content
    else
      context.response = description: "not found"

resource = Fn.tee ( context ) ->
  # console.log "sky-classifier: resource"
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
      # add target and url if we don't already have one
      request.target ?= context.resource.encode request.resource.bindings
      request.url ?= url request.domain, request.target
    else
      context.response = description: "not found"

options = Fn.tee ( context ) ->
  # console.log "sky-classifier: options"
  { request, resource } = context
  if request.method == "options"
    # console.log "OPTIONS REQUEST", request
    # TODO do we need to avoid sending the CORS header
    #      if it isn't a CORS request?
    # TODO we should be basing the headers on the
    # api description
    context.response =
      description: "no content"
      headers:
        "access-control-allow-methods": [ "*" ]
        "access-control-allow-origin": [ request.headers.origin[0] ]
        "access-control-allow-credentials": [ true ]
        "access-control-expose-headers": [ "*" ]
        "access-control-max-age": [ 7200 ]
        "access-control-allow-headers": [ "Authorization", "*" ]

head = Fn.tee ( context ) ->
  # console.log "sky-classifier: head"
  { request } = context
  context.head = if request.method == "head"
    request.method = "get"
    true
  else false

method = Fn.tee ( context ) ->
  # console.log "sky-classifier: method"
  { request, resource } = context
  if ( method = resource.methods[ request.method ])?
    context.method = method
  else
    context.response =
      description: "method not allowed"
      headers:
        allow: [ resources.options ]

acceptable = Fn.tee ( context ) ->
  # console.log "sky-classifier: acceptable"
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
  # console.log "sky-classifier: supported"
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
    # console.log "sky-classifier: accept"
    { accept, response, request } = context
    if response.content? && accept? && ( Sublime.Response.Status.ok response )
      if ( type = Accept.select accept, "text/html" )? && request.resource.name == "description"
        Sublime.Response.Headers.set response, "content-type", MediaType.format type
        response.content = await descriptionHTML response.content
      else
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

valid = Fn.tee ( context ) ->
  # console.log "sky-classifier: valid"
  { request, method } = context
  if request.content?
    if method.request.schema?
      if !( validator.validate method.request.schema, request.content )
        context.response = 
          description: "bad request"

consistent = Fn.tee ( context ) ->
  # console.log "sky-classifier: consistent"
  { request } = context
  if request.content?
    if Type.isObject request.content
      for key, value of request.content
        if request.resource.bindings[ key ]? 
          if request.resource.bindings[ key ] != value
            context.response =
              description: "conflict"
            return
      
authorization = Fn.tee ( context ) ->
  # console.log "sky-classifier: authorization"
  { request } = context
  context.request.authorization ?= do ->
    if ( header = Sublime.Request.Headers.get request, "authorization" )?
      authorization = Authorization.parse header
      if authorization.scheme == "credentials"
        JSON64
          .decode authorization.token
          .map ( value ) -> Authorization.parse value
      else
        [ authorization ]
    else []

invoke = Fn.curry Fn.rtee ( handler, context ) ->
  # console.log "sky-classifier: invoke"
  { request } = context
  request.api = context.api
  context.response = await handler request
  await accept context
  if context.head
    # let Sublime take care of the rest
    context.response.description = "no content"

run = Fn.curry ( processors, context ) ->
  stack = []
  if checkStack context, stack
    stack.push context.request
    for processor in processors
      context = await processor context
      break if context.response?
    stack.pop()
    context.response
  else
    console.warn "sky-classifier: request matches 
      existing request", context.request
    context.response = description: "internal server error"
    
initialize = Fn.curry ( context, request ) ->
  { ( structuredClone context )..., request }

classifier = ( context, handler ) ->
  Fn.flow [
    initialize context
    run [
      ping
      # we'll need to move this back down once we compute meaningful
      # responses for CORS headers
      options
      lambda
      describe
      resource
      head
      method
      acceptable
      supported
      valid
      consistent
      authorization
      invoke handler
    ]    
    Sublime.response
    normalize
  ]

export { classifier }
