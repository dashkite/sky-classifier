import * as Fn from "@dashkite/joy/function"
import { Router } from "@pandastrike/router"

buildRouter = ( description ) ->
  router = Router.create()
  for name, resource of description.resources
    router.add
      template: resource.template
      data: { name, resource }
  router

matchAccept = ( actual, expected ) -> true

matchMediaType = ( actual, expected ) -> true

# IMPORTANT options and head methods should be handled outside the classifier
# since these are basically variants of the other methods

classify = ( description ) ->
  router = buildRouter description
  ( request ) ->
    console.log "start classifier"
    console.log { request }
    if (match = router.match request.target)?
      console.log { match }
      { resource, name } = match.data
      if (method = resource.methods[ request.method ])?
        { signatures } = method
        acceptable = do ->
          if signatures.response[ "content-type" ]?
            matchAccept request.headers.accept,
              signatures.response[ "content-type" ]
          else
            true
        if acceptable
          supported = do ->
            if signatures.request["content-type"]?
              matchMediaType request.headers[ "content-type" ], 
                signatures.request["content-type"]
            else
              true
          if supported
            resource: name
            method: request.method
            bindings: match.bindings
          else
            "unsupported media type"
        else
          "not acceptable"
      else
        "method not allowed"
    else
      "not found"

export default classify
