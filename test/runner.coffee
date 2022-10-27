import assert from "@dashkite/assert"
# import * as Type from "@dashkite/joy/type"

runner = ( dispatch ) ->
  ( scenario ) -> 
    { request, response: { status, content }} = scenario
    ->
      response = await dispatch request
      assert.equal status, response.status
      if content?
        if content.body?
          assert.deepEqual content.body, response.content
        # if response.content.length?
        #   assert.equal response.content.length,
        #     response.headers[ "content-length" ]
        assert.equal content.type,
          response.headers[ "content-type" ][0]
      else
        assert !response.content?
        assert !response.headers[ "content-length" ]?
        assert !response.headers[ "content-type" ]?
  
export default runner