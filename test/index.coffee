import { test, success } from "@dashkite/amen"
import print from "@dashkite/amen-console"

import dispatcher from "@dashkite/sky-dispatcher"

# MUT
import { classifier } from "../src"

import scenarios from "./scenarios"
import api from "./api"
import handlers from "./handlers"
import runner from "./runner"

lambdas = "acme.io": "acme-api-lambda"

# mock fetch that just runs locally
globalThis.Sky =
  fetch: dispatcher { description: api, handlers }

# we would usually pass in another handler,
# but for test purposes we just skip ahead
# to our mock fetch
run = runner classifier { lambdas }, Sky.fetch

do ->

  print await test "Sky Dispatcher", do ->
    for scenario in scenarios
      scenario.request.domain = "acme.io"
      test scenario.name, run scenario

  process.exit success