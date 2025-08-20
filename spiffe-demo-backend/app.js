const express = require("express");
const fs = require("fs");
const crypto = require("crypto");
const { GRPC: Cerbos } = require("@cerbos/grpc");

const app = express();
const port = 8080;

app.use(express.json());

let cerbosClient;

async function initializeCerbos() {
  try {
    const host = process.env.CERBOS_HOST || "localhost:3593";
    cerbosClient = new Cerbos(host, {
      tls: false,
    });
    console.log(`Connected to Cerbos at ${host}`);
  } catch (error) {
    console.error("Failed to connect to Cerbos:", error);
  }
}

function extractSPIFFEId() {
  try {
    const certPath = "/var/run/secrets/spiffe.io/tls.crt";

    if (!fs.existsSync(certPath)) {
      throw new Error("SPIFFE certificate not found");
    }

    const certPem = fs.readFileSync(certPath, "utf8");
    const cert = new crypto.X509Certificate(certPem);

    const subjectAltName = cert.subjectAltName;
    if (subjectAltName) {
      const uriMatch = subjectAltName.match(/URI:([^,]+)/);
      if (uriMatch) {
        return uriMatch[1].trim();
      }
    }

    throw new Error("SPIFFE ID not found in certificate");
  } catch (error) {
    throw new Error(`Failed to extract SPIFFE ID: ${error.message}`);
  }
}

async function authorizeRequest(principal, resource, action, context = {}) {
  if (!cerbosClient) {
    throw new Error("Cerbos client not initialized");
  }

  const request = {
    principal: {
      id: principal.id,
      roles: principal.roles || [],
      attributes: principal.attributes || {},
    },
    resource: {
      kind: resource.kind,
      id: resource.id,
      attributes: resource.attributes || {},
    },
    actions: [action],
    auxData: context,
  };

  try {
    const result = await cerbosClient.checkResource(request);
    return result.isAllowed(action);
  } catch (error) {
    console.error("Authorization error:", error);
    return false;
  }
}

app.get("/health", (req, res) => {
  res.json({ status: "healthy", timestamp: new Date().toISOString() });
});

app.get("/api/resources", async (req, res) => {
  try {
    const spiffeId = extractSPIFFEId();
    const principal = {
      id: spiffeId,
      roles: ["api"],
      attributes: {},
    };

    const isAuthorized = await authorizeRequest(
      principal,
      { kind: "resource", id: "all" },
      "read"
    );

    if (!isAuthorized) {
      return res.status(403).json({ error: "Access denied" });
    }

    res.json({
      message: "Resources retrieved successfully",
      spiffeId: spiffeId,
      data: [
        { id: 1, name: "Resource 1", type: "document" },
        { id: 2, name: "Resource 2", type: "image" },
        { id: 3, name: "Resource 3", type: "video" },
      ],
    });
  } catch (error) {
    console.error("Error in /api/resources:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

initializeCerbos().then(() => {
  app.listen(port, () => {
    console.log(`SPIFFE Demo Backend listening at http://localhost:${port}`);
  });
});
