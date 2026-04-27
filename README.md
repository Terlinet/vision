# TerlineT Vision

Este projeto combina **Flutter** para o aplicativo móvel e **Python (YOLOv8)** para o processamento de visão computacional.

## Estrutura do Projeto

- `backend/`: Script Python usando Flask e YOLOv8.
- `lib/`: Código-fonte do app Flutter.
- `pubspec.yaml`: Dependências do Flutter.

## Como Executar

### 1. Backend (Python)
Certifique-se de ter o Python instalado.
```bash
cd backend
pip install -r requirements.txt
python app.py
```
O servidor rodará em `http://localhost:5000`.

### 2. Frontend (Flutter)
1. Certifique-se de ter o Flutter instalado.
2. No diretório raiz, execute:
```bash
flutter pub get
flutter run
```

**Nota sobre IPs:**
- No emulador Android, `10.0.2.2` aponta para o localhost do seu PC.
- Para usar um dispositivo físico, mude `_apiUrl` em `lib/main.dart` para o IP da sua máquina na rede local.
