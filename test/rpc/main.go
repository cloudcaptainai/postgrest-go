package main

import (
	"fmt"

	postgrest "github.com/cloudcaptainai/postgrest-go"
)

var (
	REST_URL = `http://localhost:3000`
)

func main() {
	client := postgrest.NewClientFast(REST_URL, "", nil)
	if client.ClientError != nil {
		panic(client.ClientError)
	}

	result := client.Rpc("add_them", "", map[string]int{"a": 9, "b": 3})
	if client.ClientError != nil {
		panic(client.ClientError)
	}

	fmt.Println(result)
}
