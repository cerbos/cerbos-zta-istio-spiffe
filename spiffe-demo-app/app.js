const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const port = 8080;

app.use(express.static('public'));

function getSPIFFEIdentity() {
    try {
        const certPath = '/var/run/secrets/spiffe.io/tls.crt';
        const keyPath = '/var/run/secrets/spiffe.io/tls.key';
        
        if (!fs.existsSync(certPath)) {
            return { error: 'SPIFFE certificate not found' };
        }

        const certPem = fs.readFileSync(certPath, 'utf8');
        const cert = new crypto.X509Certificate(certPem);
        
        // Extract issuer information
        const issuer = `Issuer: ${cert.issuer}`;

        // Extract URI (SPIFFE ID) from Subject Alternative Names
        let spiffeId = 'URI: Not found';
        const subjectAltName = cert.subjectAltName;
        if (subjectAltName) {
            const uriMatch = subjectAltName.match(/URI:([^,]+)/);
            if (uriMatch) {
                spiffeId = `URI: ${uriMatch[1].trim()}`;
            }
        }

        // Extract subject
        const subject = `Subject: ${cert.subject}`;

        // Extract validity dates
        const validity = [
            `notBefore=${cert.validFrom}`,
            `notAfter=${cert.validTo}`
        ];

        // Get certificate serial number
        const serial = `serial=${cert.serialNumber}`;

        return {
            issuer,
            spiffeId,
            subject,
            validity,
            serial,
            certificatePresent: true,
            keyPresent: fs.existsSync(keyPath)
        };
    } catch (error) {
        return { error: error.message };
    }
}

app.get('/api/identity', (req, res) => {
    const identity = getSPIFFEIdentity();
    res.json(identity);
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, () => {
    console.log(`SPIFFE Demo App listening at http://localhost:${port}`);
});