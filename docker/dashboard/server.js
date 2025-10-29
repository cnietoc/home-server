const express = require('express');
const fs = require('fs');
const path = require('path');
const yaml = require('yaml');
const { execSync } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuración
const CONFIG_PATH = '/config/stacks.yml';
const BASE_DOMAIN = process.env.BASE_DOMAIN || 'apocaly.net';

// Middleware para servir archivos estáticos
app.use(express.static('public'));
app.use(express.json());

// Función para leer la configuración de stacks
function loadStacksConfig() {
    try {
        if (fs.existsSync(CONFIG_PATH)) {
            const configContent = fs.readFileSync(CONFIG_PATH, 'utf8');
            return yaml.parse(configContent);
        }
        return { stacks: {} };
    } catch (error) {
        console.error('Error loading stacks config:', error.message);
        return { stacks: {} };
    }
}

// Función para obtener información del sistema
function getSystemInfo() {
    try {
        const info = {};

        // Información básica del sistema
        try {
            info.hostname = execSync('hostname', { encoding: 'utf8' }).trim();
        } catch (e) {
            info.hostname = 'unknown';
        }

        try {
            info.uptime = execSync('uptime -p', { encoding: 'utf8' }).trim();
        } catch (e) {
            info.uptime = 'unknown';
        }

        try {
            const memInfo = execSync('free -h', { encoding: 'utf8' });
            const memLines = memInfo.split('\n');
            const memLine = memLines.find(line => line.startsWith('Mem:'));
            if (memLine) {
                const memParts = memLine.split(/\s+/);
                info.memory = {
                    total: memParts[1],
                    used: memParts[2],
                    available: memParts[6] || memParts[3]
                };
            }
        } catch (e) {
            info.memory = { total: 'unknown', used: 'unknown', available: 'unknown' };
        }

        try {
            const diskInfo = execSync('df -h /', { encoding: 'utf8' });
            const diskLines = diskInfo.split('\n');
            const diskLine = diskLines[1];
            if (diskLine) {
                const diskParts = diskLine.split(/\s+/);
                info.disk = {
                    total: diskParts[1],
                    used: diskParts[2],
                    available: diskParts[3],
                    usage: diskParts[4]
                };
            }
        } catch (e) {
            info.disk = { total: 'unknown', used: 'unknown', available: 'unknown', usage: 'unknown' };
        }

        // Información de Docker
        try {
            const dockerInfo = execSync('docker info --format "{{.Containers}}"', { encoding: 'utf8' }).trim();
            info.docker = {
                containers: dockerInfo || '0'
            };

            const runningContainers = execSync('docker ps -q | wc -l', { encoding: 'utf8' }).trim();
            info.docker.running = runningContainers || '0';
        } catch (e) {
            info.docker = { containers: 'unknown', running: 'unknown' };
        }

        info.timestamp = new Date().toISOString();
        return info;
    } catch (error) {
        console.error('Error getting system info:', error.message);
        return {
            hostname: 'unknown',
            uptime: 'unknown',
            memory: { total: 'unknown', used: 'unknown', available: 'unknown' },
            disk: { total: 'unknown', used: 'unknown', available: 'unknown', usage: 'unknown' },
            docker: { containers: 'unknown', running: 'unknown' },
            timestamp: new Date().toISOString()
        };
    }
}

// Función para construir URLs de servicios
function buildServiceUrl(subdomain) {
    if (!subdomain || subdomain === '') {
        return `https://${BASE_DOMAIN}`;
    }
    return `https://${subdomain}.${BASE_DOMAIN}`;
}

// Función para procesar stacks y servicios
function processStacksAndServices() {
    const config = loadStacksConfig();
    const stacks = [];

    if (config.stacks) {
        Object.entries(config.stacks).forEach(([stackName, stackConfig]) => {
            const stack = {
                name: stackName,
                description: stackConfig.description || 'Sin descripción',
                config_files: Array.isArray(stackConfig.config_files)
                    ? ['common', ...stackConfig.config_files].join(',')
                    : 'common',
                services: []
            };

            if (stackConfig.services) {
                Object.entries(stackConfig.services).forEach(([serviceName, serviceConfig]) => {
                    const service = {
                        name: serviceName,
                        description: serviceConfig.description || serviceName,
                        protected: serviceConfig.protected || false,
                        subdomain: serviceConfig.subdomain
                    };

                    // Solo agregar URL si tiene subdomain o es el servicio principal
                    if (serviceConfig.subdomain !== undefined) {
                        service.url = buildServiceUrl(serviceConfig.subdomain);
                        service.hasUrl = true;
                    } else {
                        service.hasUrl = false;
                    }

                    stack.services.push(service);
                });
            }

            stacks.push(stack);
        });
    }

    return stacks;
}

// API Endpoints
app.get('/api/system', (req, res) => {
    const systemInfo = getSystemInfo();
    res.json(systemInfo);
});

app.get('/api/stacks', (req, res) => {
    const stacks = processStacksAndServices();
    res.json(stacks);
});

app.get('/api/dashboard', (req, res) => {
    const systemInfo = getSystemInfo();
    const stacks = processStacksAndServices();

    res.json({
        system: systemInfo,
        stacks: stacks,
        generated_at: new Date().toISOString()
    });
});

// Ruta principal - servir el dashboard HTML
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
    console.log(`🏠 Home Server Dashboard running on port ${PORT}`);
    console.log(`📊 API endpoints:`);
    console.log(`   - GET /api/system - System information`);
    console.log(`   - GET /api/stacks - Stacks and services`);
    console.log(`   - GET /api/dashboard - Complete dashboard data`);
});

// Manejo de errores
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
