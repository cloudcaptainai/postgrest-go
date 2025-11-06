// This is basic example for postgrest-go library usage.
// For now this example is represent wanted syntax and bindings for library.
// After core development this test files will be used for CI tests.

package main

import (
	"fmt"

	postgrest "github.com/cloudcaptainai/postgrest-go"
)

var (
	RestUrl = `http://localhost:3000`
	headers = map[string]string{}
	schema  = "public"
)

func main() {
	client := postgrest.NewClientFast(RestUrl, schema, headers)
	client.SetFastHTTPMaxConns(100)

	res, _, err := client.From("actor").Select("actor_id,first_name", "", false).ExecuteString()
	if err != nil {
		panic(err)
	}

	fmt.Println(res)
}
