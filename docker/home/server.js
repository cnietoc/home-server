const express = require('express');
const fs = require('fs');
const path = require('path');
const yaml = require('yaml');
const { execSync } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuración
const CONFIG_PATH = '/config/stacks.yml';
const BASE_DOMAIN = process.env.BASE_DOMAIN;

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

// Función para obtener información del sistema (segura)
function getSystemInfo() {
    try {
        const info = {};

        // Información básica del sistema (sin hostname real por seguridad)
        info.serverName = 'Home Server';

        try {
            const uptime = execSync('uptime -p', { encoding: 'utf8' }).trim();
            info.uptime = uptime.replace('up ', '');
        } catch (e) {
            info.uptime = 'unknown';
        }

        // Memoria (solo porcentajes, no cantidades absolutas)
        try {
            const memInfo = execSync('free', { encoding: 'utf8' });
            const memLines = memInfo.split('\n');
            const memLine = memLines.find(line => line.startsWith('Mem:'));
            if (memLine) {
                const memParts = memLine.split(/\s+/).map(Number);
                const total = memParts[1];
                const used = memParts[2];
                const usagePercent = Math.round((used / total) * 100);

                info.memory = {
                    usage: `${usagePercent}%`,
                    status: usagePercent > 80 ? 'high' : usagePercent > 60 ? 'medium' : 'low'
                };
            }
        } catch (e) {
            info.memory = { usage: 'unknown', status: 'unknown' };
        }

        // Disco (solo del sistema de archivos root)
        try {
            const diskInfo = execSync('df -h /', { encoding: 'utf8' });
            const diskLines = diskInfo.split('\n');
            const diskLine = diskLines[1];
            if (diskLine) {
                const diskParts = diskLine.split(/\s+/);
                const usagePercent = parseInt(diskParts[4].replace('%', ''));

                info.disk = {
                    usage: diskParts[4],
                    available: diskParts[3],
                    status: usagePercent > 85 ? 'high' : usagePercent > 70 ? 'medium' : 'low'
                };
            }
        } catch (e) {
            info.disk = { usage: 'unknown', available: 'unknown', status: 'unknown' };
        }

        // Estado general del sistema
        try {
            const loadAvg = execSync('cat /proc/loadavg', { encoding: 'utf8' }).trim().split(' ')[0];
            const load = parseFloat(loadAvg);
            info.load = {
                value: load.toFixed(2),
                status: load > 2.0 ? 'high' : load > 1.0 ? 'medium' : 'low'
            };
        } catch (e) {
            info.load = { value: 'unknown', status: 'unknown' };
        }

        // Información básica de Docker (solo conteos)
        try {
            const runningContainers = execSync('docker ps -q | wc -l', { encoding: 'utf8' }).trim();
            const totalContainers = execSync('docker ps -a -q | wc -l', { encoding: 'utf8' }).trim();

            info.containers = {
                running: parseInt(runningContainers) || 0,
                total: parseInt(totalContainers) || 0
            };
        } catch (e) {
            info.containers = { running: 0, total: 0 };
        }

        info.lastUpdated = new Date().toISOString();
        return info;
    } catch (error) {
        console.error('Error getting system info:', error.message);
        return {
            serverName: 'Home Server',
            uptime: 'unknown',
            memory: { usage: 'unknown', status: 'unknown' },
            disk: { usage: 'unknown', available: 'unknown', status: 'unknown' },
            load: { value: 'unknown', status: 'unknown' },
            containers: { running: 0, total: 0 },
            lastUpdated: new Date().toISOString()
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

// Función para procesar servicios web accesibles
function processAccessibleServices() {
    const config = loadStacksConfig();
    const publicServices = [];
    const protectedServices = [];

    if (config.stacks) {
        Object.entries(config.stacks).forEach(([stackName, stackConfig]) => {
            if (stackConfig.services) {
                Object.entries(stackConfig.services).forEach(([serviceName, serviceConfig]) => {
                    // Solo incluir servicios que tienen subdomain definido (accesibles vía web)
                    if (serviceConfig.subdomain !== undefined) {
                        const service = {
                            name: serviceConfig.description || serviceName,
                            url: buildServiceUrl(serviceConfig.subdomain),
                            stack: stackName
                        };

                        // Separar por protección
                        if (serviceConfig.protected) {
                            protectedServices.push(service);
                        } else {
                            publicServices.push(service);
                        }
                    }
                });
            }
        });
    }

    return { publicServices, protectedServices };
}

// API Endpoints
app.get('/api/system', (req, res) => {
    const systemInfo = getSystemInfo();
    res.json(systemInfo);
});

app.get('/api/services', (req, res) => {
    const services = processAccessibleServices();
    res.json(services);
});

app.get('/api/dashboard', (req, res) => {
    const systemInfo = getSystemInfo();
    const services = processAccessibleServices();

    res.json({
        system: systemInfo,
        services: services,
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
    console.log(`   - GET / - Main dashboard`);
    console.log(`   - GET /api/system - System status (safe information)`);
    console.log(`   - GET /api/services - Accessible web services`);
    console.log(`   - GET /api/dashboard - Complete dashboard data`);
});

// Manejo de errores
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
