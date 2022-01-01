import { test, success } from "@dashkite/amen"
import print from "@dashkite/amen-console"
import assert from "@dashkite/assert"

import $ from "../src"

api = 
  resources:
    foo:
      template: "/foo"
      methods:
        post:
          signatures:
            request: {}
            response:
              status: [ 200 ]

do ->

  print await test "Sky Classifier", [

    test "create a classifier from a description", ->
      classify = $ api
      assert.deepEqual { resource: "foo", method: "post", bindings: {} },
        classify
          target: "/foo"
          method: "post"
          headers: {}


    
  ]

  process.exit success