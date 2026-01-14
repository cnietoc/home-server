FROM justarchi/archisteamfarm:latest

# Instalar bash para el entrypoint
USER root
RUN apk add --no-cache bash

# Copiar templates de configuración (archivos .json con variables $)
COPY ASF.json /app/ASF.json
COPY DefaultBot.json /app/DefaultBot.json

# Copiar script de entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Volver al usuario de ASF
USER asf

# Usar nuestro entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["dotnet", "/app/ArchiSteamFarm.dll"]
