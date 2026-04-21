const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const HMS_API_URL = process.env.HMS_API_URL || 'http://hms:8080';

// Middleware
app.use(express.static('public'));
app.use(express.json());

async function fetchWithTimeout(url, options = {}, timeoutMs = 3000) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetch(url, { ...options, signal: controller.signal });
        if (!response.ok) {
            throw new Error(`HMS API error ${response.status}`);
        }
        return await response.json();
    } finally {
        clearTimeout(timeout);
    }
}

// API Endpoints
app.get('/api/dashboard', async (req, res) => {
    try {
        const data = await fetchWithTimeout(`${HMS_API_URL}/api/dashboard`);
        res.json(data);
    } catch (error) {
        console.error('Error fetching HMS dashboard:', error.message);
        res.status(502).json({
            error: 'No se pudo obtener el estado del HMS',
            detail: error.message
        });
    }
});

app.get('/api/metrics', async (req, res) => {
    try {
        const data = await fetchWithTimeout(`${HMS_API_URL}/api/metrics`);
        res.json(data);
    } catch (error) {
        console.error('Error fetching metrics:', error.message);
        res.status(502).json({ error: 'No se pudieron obtener métricas' });
    }
});

app.get('/api/stacks/:name/up', async (req, res) => {
    try {
        await fetchWithTimeout(`${HMS_API_URL}/api/stacks/${req.params.name}/up`, { method: 'POST' }, 60000);
        res.redirect('/');
    } catch (error) {
        console.error(`Error starting stack ${req.params.name}:`, error.message);
        res.redirect('/');
    }
});

app.get('/api/stacks/:name/down', async (req, res) => {
    try {
        await fetchWithTimeout(`${HMS_API_URL}/api/stacks/${req.params.name}/down`, { method: 'POST' }, 60000);
        res.redirect('/');
    } catch (error) {
        console.error(`Error stopping stack ${req.params.name}:`, error.message);
        res.redirect('/');
    }
});

// Ruta principal
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
    console.log(`🏠 Home Server Dashboard running on port ${PORT}`);
    console.log(`📊 Endpoints:`);
    console.log(`   - GET / - Dashboard HTML`);
    console.log(`   - GET /api/dashboard - HMS dashboard proxy`);
});

// Manejo de errores
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
