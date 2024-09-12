# apigateway

## Imagen nativa
Para generar la imagen nativa se debe tener instalado GraalVM y configurado en el sistema. Luego se debe ejecutar el siguiente comando:
```shell
sdk use java 21.0.2-graalce
./mvnw spring-boot:build-image -Pnative
```