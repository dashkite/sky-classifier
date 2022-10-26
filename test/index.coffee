import { test, success } from "@dashkite/amen"
import print from "@dashkite/amen-console"
import assert from "@dashkite/assert"

import * as Type from "@dashkite/joy/type"

import $ from "../src"

import scenarios from "./scenarios"
import api from "./api"

handlers =
  foo:
    post: -> 
      description: "ok"
      content: "success!"
    delete: ->
  bar:
    get: ->
      content: greeting: "hello, world!"

dispatch = $ api, handlers

run = ( scenario ) -> ->
  response = await dispatch scenario.request
  assert.equal scenario.response.status, response.status
  if scenario.response.content?
    if scenario.response.content.body?
      if Type.isObject response.content
        assert.deepEqual scenario.response.content.body,
          response.content
      else
        assert.equal scenario.response.content.body,
          response.content
    if response.content.length?
      assert.equal response.content.length,
        response.headers[ "content-length" ]
    assert.equal scenario.response.content.type,
      response.headers[ "content-type" ][0]
  else
    assert !response.content?
    assert !response.headers[ "content-length" ]?
    assert !response.headers[ "content-type" ]?
  
do ->

  print await test "Sky Dispatcher", do ->
    for scenario in scenarios
      test scenario.name, run scenario

  process.exit success