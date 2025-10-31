package main

import (
	"testing"

	"github.com/cerbos/cerbos-sdk-go/cerbos"
	effectv1 "github.com/cerbos/cerbos/api/genpb/cerbos/effect/v1"
	enginev1 "github.com/cerbos/cerbos/api/genpb/cerbos/engine/v1"
	responsev1 "github.com/cerbos/cerbos/api/genpb/cerbos/response/v1"
	"google.golang.org/protobuf/types/known/structpb"
)

func TestExtractIdentities(t *testing.T) {
	t.Run("by identity", func(t *testing.T) {
		header := `By=spiffe://demo.cerbos.io/ns/sandbox/sa/backend;Hash=abc;Subject="";URI=spiffe://demo.cerbos.io/ns/istio/sa/ingress`
		principal, resource, err := extractIdentities(header)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if principal != "spiffe://demo.cerbos.io/ns/istio/sa/ingress" {
			t.Fatalf("unexpected principal: %s", principal)
		}
		if resource != "spiffe://demo.cerbos.io/ns/sandbox/sa/backend" {
			t.Fatalf("unexpected resource: %s", resource)
		}
	})

	t.Run("missing resource identity", func(t *testing.T) {
		header := `URI=spiffe://demo.cerbos.io/ns/sandbox/sa/backend`
		if _, _, err := extractIdentities(header); err == nil {
			t.Fatal("expected error when resource identity missing")
		}
	})

	t.Run("missing principal identity", func(t *testing.T) {
		header := `By=spiffe://demo.cerbos.io/ns/sandbox/sa/backend`
		if _, _, err := extractIdentities(header); err == nil {
			t.Fatal("expected error when principal identity missing")
		}
	})

	t.Run("multiple entries", func(t *testing.T) {
		header := `By=spiffe://demo.cerbos.io/ns/sandbox/sa/first;URI=spiffe://demo.cerbos.io/ns/istio/sa/ingress,By=spiffe://demo.cerbos.io/ns/other/sa/service`
		principal, resource, err := extractIdentities(header)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if principal != "spiffe://demo.cerbos.io/ns/istio/sa/ingress" {
			t.Fatalf("unexpected principal: %s", principal)
		}
		if resource != "spiffe://demo.cerbos.io/ns/sandbox/sa/first" {
			t.Fatalf("unexpected resource: %s", resource)
		}
	})

	t.Run("missing spiffe id", func(t *testing.T) {
		if _, _, err := extractIdentities("By=foo;URI=bar"); err == nil {
			t.Fatal("expected error when no SPIFFE ID present")
		}
	})
}

func TestBuildResponseHeaders(t *testing.T) {
	outputs := []*enginev1.OutputEntry{
		{
			Src: "headers",
			Val: &structpb.Value{
				Kind: &structpb.Value_StructValue{
					StructValue: &structpb.Struct{
						Fields: map[string]*structpb.Value{
							"X-Trace": structpb.NewStringValue("trace-123"),
							"Empty":   structpb.NewStringValue(""),
						},
					},
				},
			},
		},
		{
			Src: "audit",
			Val: structpb.NewStringValue("captured"),
		},
	}

	rr := &cerbos.ResourceResult{
		CheckResourcesResponse_ResultEntry: &responsev1.CheckResourcesResponse_ResultEntry{
			Actions: map[string]effectv1.Effect{"read": effectv1.Effect_EFFECT_ALLOW},
			Outputs: outputs,
		},
	}

	headers := buildResponseHeaders(rr)
	if len(headers) != 2 {
		t.Fatalf("expected 2 headers, got %d", len(headers))
	}

	headerMap := make(map[string]string, len(headers))
	for _, h := range headers {
		headerMap[h.Header.GetKey()] = h.Header.GetValue()
	}

	if headerMap["x-trace"] != "trace-123" {
		t.Fatalf("missing x-trace header: %#v", headerMap)
	}

	if headerMap[fallbackHeaderKey] != "captured" {
		t.Fatalf("missing fallback header: %#v", headerMap)
	}
}

func TestFlattenValue(t *testing.T) {
	structVal := &structpb.Value{
		Kind: &structpb.Value_StructValue{
			StructValue: &structpb.Struct{
				Fields: map[string]*structpb.Value{
					"Foo": structpb.NewStringValue("bar"),
				},
			},
		},
	}
	fields := flattenValue(structVal)
	if len(fields) != 1 || fields["Foo"] != "bar" {
		t.Fatalf("unexpected flattened struct: %#v", fields)
	}

	scalarVal := structpb.NewNumberValue(42)
	scalar := flattenValue(scalarVal)
	if len(scalar) != 1 || scalar[fallbackHeaderKey] != "42" {
		t.Fatalf("unexpected fallback flatten: %#v", scalar)
	}
}

func TestStringifyValue(t *testing.T) {
	if got := stringifyValue(structpb.NewStringValue("value")); got != "value" {
		t.Fatalf("expected string value, got %s", got)
	}
	if got := stringifyValue(structpb.NewNumberValue(3.14)); got != "3.14" {
		t.Fatalf("expected float string, got %s", got)
	}
	if got := stringifyValue(structpb.NewBoolValue(true)); got != "true" {
		t.Fatalf("expected bool string, got %s", got)
	}
	if got := stringifyValue(structpb.NewNullValue()); got != "" {
		t.Fatalf("expected empty string for nil, got %s", got)
	}
	mapVal := &structpb.Value{
		Kind: &structpb.Value_StructValue{
			StructValue: &structpb.Struct{
				Fields: map[string]*structpb.Value{
					"foo": structpb.NewStringValue("bar"),
				},
			},
		},
	}
	if got := stringifyValue(mapVal); got == "" {
		t.Fatal("expected json representation for complex type")
	}
}
