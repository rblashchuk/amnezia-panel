# Планирование Amnezia Panel

## Цель

Превратить текущую read-only панель трафика в полноценную локальную
админ-панель для self-hosted серверов AmneziaVPN, сохранив совместимость с
официальным Amnezia-клиентом.

При этом нужно сохранить исходную ключевую ценность проекта: постоянный сбор и
хранение истории трафика, которого нет в Amnezia-клиенте.

## Целевая архитектура

### VPS collector

Компонент на VPS обязателен и остается частью продукта.

Зона ответственности:

- Запускается на VPS рядом с контейнерами Amnezia.
- Собирает метрики трафика через `wg show all dump` и `awg show all dump`.
- Хранит историю трафика в SQLite.
- Отдает локальному компоненту read-only метрики и состояние пиров.
- Опционально отдает read-only health, список источников, версию и metadata
  клиентов.

Что не делаем в первой admin-версии:

- Не превращаем collector в привилегированный admin API.
- Не храним SSH credentials на VPS collector.
- Не выполняем из collector операции создания, удаления и изменения VPN config.

### Локальный admin daemon / CLI

Локальный компонент запускается на машине пользователя и отдает web UI на
`127.0.0.1`.

Зона ответственности:

- Отдает текущую React-панель локально.
- Получает метрики от VPS collector.
- Подключается к VPS по SSH для admin-операций.
- Устанавливает и обновляет VPS collector.
- Создает, удаляет, переименовывает и экспортирует клиентские конфиги.
- Хранит локальные профили подключения и локальные секреты.

### Browser UI

Браузер общается только с локальным компонентом. Для пользователя это выглядит
как единая админ-панель на localhost:

- Графики трафика.
- Список пиров/клиентов.
- Человекочитаемые имена клиентов.
- Создание, удаление и переименование клиентов.
- Экспорт конфигов и QR-код.

## Итоги reverse engineering

Self-hosted администрирование Amnezia не построено на публичном server API.
Официальный клиент подключается к VPS по SSH, управляет Docker-контейнерами,
читает и пишет файлы внутри контейнеров и выполняет protocol-specific команды.

Важные области кода Amnezia:

- `client/core/controllers/selfhosted/installController.cpp`
- `client/core/controllers/selfhosted/usersController.cpp`
- `client/core/controllers/selfhosted/exportController.cpp`
- `client/core/configurators/wireguardConfigurator.cpp`
- `client/core/configurators/awgConfigurator.cpp`
- `client/core/configurators/xrayConfigurator.cpp`
- `client/core/configurators/openVpnConfigurator.cpp`
- `client/core/utils/selfhosted/sshSession.cpp`

## Имена клиентов

Amnezia хранит человекочитаемые имена клиентов в отдельном JSON-файле внутри
каждого контейнера:

- WireGuard: `/opt/amnezia/wireguard/clientsTable`
- AWG/AWG2: `/opt/amnezia/awg/clientsTable`
- OpenVPN: `/opt/amnezia/openvpn/clientsTable`
- Xray: `/opt/amnezia/xray/clientsTable`

Текущий формат:

```json
[
  {
    "clientId": "public-key-or-uuid-or-cert-id",
    "userData": {
      "clientName": "Alice iPhone",
      "creationDate": "Wed Jun 17 12:34:56 2026",
      "latestHandshake": "5m",
      "dataReceived": "1.2 MiB",
      "dataSent": "4.8 MiB",
      "allowedIps": "10.8.1.3/32"
    }
  }
]
```

Legacy-формат, который виден в миграционной логике Amnezia:

```json
{
  "client-id": {
    "clientName": "Alice iPhone"
  }
}
```

Требования к реализации:

- Читать и текущий, и legacy-формат.
- Писать текущий array-формат.
- Использовать `clientId` как ключ для join.
- Для WireGuard/AWG `clientId` равен public key пира.
- Считать `clientsTable` authoritative-источником display names.
- При обновлениях сохранять неизвестные поля.

## Правила совместимости

Админ-панель должна менять те же server-side артефакты, что и Amnezia-клиент.

Общие правила:

- Перед каждой записью заново читать текущее состояние.
- Идентифицировать клиентов по `clientId`, а не по row/index.
- Сохранять неизвестные JSON-поля.
- По возможности загружать во временный файл и затем делать atomic move.
- После записи перечитывать файл и проверять ожидаемое состояние.
- Предпочитать Amnezia-compatible пути и форматы своим metadata-файлам.

WireGuard/AWG:

- Использовать конфиги контейнеров Amnezia как server config.
- Добавлять клиентов через append секции `[Peer]`.
- Удалять клиентов через удаление соответствующей секции `[Peer]`.
- Применять runtime-изменения через `wg syncconf wg0 <(wg-quick strip ...)`
  или `awg syncconf awg0 <(awg-quick strip ...)`.
- Обновлять `clientsTable` только после успешных protocol config changes.

Xray:

- Добавлять и удалять VLESS clients в `/opt/amnezia/xray/server.json`.
- Перезапускать Xray-контейнер после изменений.
- Обновлять `/opt/amnezia/xray/clientsTable`.

OpenVPN:

- Генерировать client key и certificate request.
- Загружать request в OpenVPN-контейнер.
- Подписывать через `easyrsa`.
- Отзывать через `easyrsa revoke` и регенерировать CRL.
- Обновлять `/opt/amnezia/openvpn/clientsTable`.

Конкурентные изменения:

- Официальный Amnezia-клиент, судя по коду, не использует строгий shared lock
  для `clientsTable`.
- Наша панель должна использовать собственный operation lock, чтобы защищать
  одновременные операции внутри панели.
- Это не полностью защищает от одновременных изменений из официального клиента,
  поэтому read-modify-write и post-write verification обязательны.

## План реализации

### Этап 1: read-only совместимость

- Добавить reader client metadata из `clientsTable`.
- Поддержать текущий и legacy-форматы.
- Соединять peer metrics с client metadata по public key.
- Возвращать имена клиентов из API.
- Обновить UI: показывать имя первым, public key оставить как технический ID.

### Этап 2: разделение Local/VPS

- Оставить VPS collector ответственным за историю метрик.
- Добавить локальный daemon/CLI mode, который отдает UI на localhost.
- Описать read-only API между локальным компонентом и VPS collector.
- Выбрать способ доступа к collector: SSH tunnel, localhost-only + tunnel,
  token auth или другой узкий транспорт.

### Этап 3: переработка installer

- Запускать установку с локальной машины.
- Интерактивно спрашивать VPS host, user, port и метод auth.
- Проверять SSH, sudo, Docker и поддерживаемые контейнеры Amnezia.
- Устанавливать или обновлять VPS collector.
- Сохранять локальный профиль подключения.

### Этап 4: WG/AWG admin-операции

- Реализовать создание клиентов для WireGuard и AWG/AWG2.
- Генерировать совместимые client configs.
- Добавлять server `[Peer]` sections.
- Применять `syncconf`.
- Обновлять `clientsTable`.
- Реализовать rename через `clientsTable`.
- Реализовать revoke/delete через server config и `clientsTable`.
- Добавить экспорт config и QR generation.

### Этап 5: мониторинг Xray и OpenVPN

- Провести отдельный reverse engineering источников runtime-метрик для Xray и
  OpenVPN.
- Для Xray проверить доступные варианты: stats API Xray-core, access logs,
  container-level counters, iptables/nftables accounting, eBPF/conntrack.
- Для OpenVPN проверить доступные варианты: management interface, status file,
  logs, container-level counters, iptables/nftables accounting.
- Выбрать source of truth для per-client traffic counters, который можно
  надежно связать с `clientsTable`.
- Реализовать read-only мониторинг Xray и OpenVPN в VPS collector.
- Добавить API и UI для отображения Xray/OpenVPN клиентов и истории трафика.

### Этап 6: Xray и OpenVPN admin-операции

- Реализовать Xray create/delete/export через Amnezia-compatible обновления
  `server.json`.
- Реализовать OpenVPN create/delete/export через `easyrsa`.
- Добавить тесты и ручные compatibility checks с официальным Amnezia-клиентом.

## Продуктовые решения

- VPS-компонент обязателен, потому что сбор истории трафика является исходной
  ключевой функцией проекта.
- В первой admin-версии VPS-компонент должен оставаться узким:
  metrics/read-only state.
- Admin-власть должна находиться в локальном компоненте и выполняться через SSH.
- Нужно воспроизводить server-side поведение Amnezia в Go, а не линковаться с
  Qt-клиентом и не автоматизировать его.
- Начинаем с WireGuard/AWG, потому что текущий проект уже поддерживает их
  метрики, а flow создания/удаления у них самый прямой.
- Для Xray и OpenVPN сначала нужно реализовать read-only мониторинг и только
  потом добавлять admin-операции.
