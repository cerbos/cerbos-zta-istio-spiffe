const express = require("express");
const { GRPC } = require("@cerbos/grpc");
const fs = require("fs");
const crypto = require("crypto");

const app = express();
const port = 3000;

app.use(express.json());
app.use(express.static("public"));

// Initialize Cerbos client
const cerbos = new GRPC(process.env.CERBOS_HOST || "localhost:3593", {
  tls: false,
});

function extractSPIFFEId() {
  try {
    const certPath = "/var/run/secrets/spiffe.io/tls.crt";
    if (!fs.existsSync(certPath)) {
      return null;
    }

    console.log("Extracting SPIFFE ID from certificate:", certPath);

    const certPem = fs.readFileSync(certPath, "utf8");
    console.log("Extracted certificate:", certPem);

    const cert = new crypto.X509Certificate(certPem);

    // Extract SPIFFE ID from Subject Alternative Names
    const subjectAltName = cert.subjectAltName;
    console.log("Subject Alt Name:", subjectAltName);

    if (subjectAltName) {
      // Extract SPIFFE ID from URI line (format: "URI:spiffe://domain/path")
      const match = subjectAltName.match(/URI:([^,\s]+)/);
      if (match) {
        const spiffeId = match[1].trim();
        console.log("Extracted SPIFFE ID:", spiffeId);
        return spiffeId;
      }
    }

    return null;
  } catch (error) {
    console.error("Error extracting SPIFFE ID:", error);
    return null;
  }
}

// Middleware to extract SPIFFE identity
app.use((req, res, next) => {
  const spiffeId = extractSPIFFEId();
  req.spiffeId = spiffeId;

  // Extract user info from SPIFFE ID
  if (spiffeId) {
    const parts = spiffeId.split("/");
    req.userInfo = {
      spiffe_id: spiffeId,
      user_id: parts[parts.length - 1] || "unknown",
      department: parts.includes("dept")
        ? parts[parts.indexOf("dept") + 1]
        : "default",
      service_type: parts.includes("service")
        ? parts[parts.indexOf("service") + 1]
        : null,
    };
  } else {
    req.userInfo = {
      spiffe_id: null,
      user_id: "anonymous",
      department: "none",
    };
  }

  next();
});

// Mock document data
const documents = [
  {
    id: "doc1",
    title: "Public Documentation",
    owner: "alice",
    department: "engineering",
    confidential_tags: [],
  },
  {
    id: "doc2",
    title: "Confidential Project Plan",
    owner: "bob",
    department: "engineering",
    confidential_tags: ["internal", "strategic"],
  },
  {
    id: "doc3",
    title: "HR Policies",
    owner: "charlie",
    department: "hr",
    confidential_tags: [],
  },
];

// Authorization check endpoint
app.post("/api/check-permission", async (req, res) => {
  try {
    const { action, resourceId } = req.body;
    const document = documents.find((d) => d.id === resourceId);

    if (!document) {
      return res.status(404).json({ error: "Document not found" });
    }

    const result = await cerbos.checkResource({
      principal: {
        id: req.userInfo.user_id,
        roles: ["user"], // In real app, this would come from your user system
        attr: req.userInfo,
      },
      resource: {
        kind: "document",
        id: resourceId,
        attr: document,
      },
      actions: [action],
    });

    const allowed = result.isAllowed(action);

    res.json({
      allowed,
      principal: req.userInfo,
      resource: document,
      action,
    });
  } catch (error) {
    console.error("Authorization check failed:", error);
    res.status(500).json({
      error: "Authorization check failed",
      details: error.message,
    });
  }
});

// Get all documents (filtered by permissions)
app.get("/api/documents", async (req, res) => {
  try {
    const authorizedDocs = [];

    for (const doc of documents) {
      const result = await cerbos.checkResource({
        principal: {
          id: req.userInfo.user_id,
          roles: ["user"],
          attr: req.userInfo,
        },
        resource: {
          kind: "document",
          id: doc.id,
          attr: doc,
        },
        actions: ["read"],
      });

      if (result.isAllowed("read")) {
        authorizedDocs.push({
          ...doc,
          permissions: {
            read: result.isAllowed("read"),
            write: result.isAllowed("write") || false,
            delete: result.isAllowed("delete") || false,
            share: result.isAllowed("share") || false,
          },
        });
      }
    }

    res.json({
      documents: authorizedDocs,
      principal: req.userInfo,
      total: authorizedDocs.length,
    });
  } catch (error) {
    console.error("Failed to get documents:", error);
    res.status(500).json({
      error: "Failed to get documents",
      details: error.message,
    });
  }
});

// Health check
app.get("/health", (req, res) => {
  res.json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    spiffe_id: req.spiffeId,
  });
});

// Current user info
app.get("/api/whoami", (req, res) => {
  res.json(req.userInfo);
});

app.listen(port, () => {
  console.log(`Cerbos demo service listening at http://localhost:${port}`);
  console.log("Current SPIFFE ID:", extractSPIFFEId());
});
