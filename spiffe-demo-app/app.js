const express = require('express');

const app = express();
const port = 8080;

const BACKEND_SERVICE_URL = process.env.BACKEND_SERVICE_URL || 'http://spiffe-demo-backend-service:80';

app.use(express.json());

app.use(express.static('public'));

app.get('/api/test-authorization', async (req, res) => {
    try {
        console.log(`Testing authorization by calling ${BACKEND_SERVICE_URL}/api/resources`);
        
        const response = await fetch(`${BACKEND_SERVICE_URL}/api/resources`, {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        const responseData = await response.json();
        
        res.json({
            success: response.ok,
            status: response.status,
            statusText: response.statusText,
            data: responseData,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        console.error('Error calling backend service:', error);
        res.json({
            success: false,
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, () => {
    console.log(`SPIFFE Cerbos Authorization Demo listening at http://localhost:${port}`);
    console.log(`Backend service URL: ${BACKEND_SERVICE_URL}`);
});