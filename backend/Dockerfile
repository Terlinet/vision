# Usa uma imagem oficial do Python
FROM python:3.10-slim

# Instala dependências do sistema necessárias para OpenCV
RUN apt-get update && apt-get install -y \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Define o diretório de trabalho
WORKDIR /app

# Copia os requisitos e instala
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia o restante do código
COPY . .

# Expõe a porta que o Hugging Face Spaces utiliza
EXPOSE 7860

# Comando para rodar a aplicação
CMD ["python", "app.py"]
