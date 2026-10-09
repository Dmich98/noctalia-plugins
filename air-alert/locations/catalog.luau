--!strict

export type Location = { key: string, name: string }

-- Names and keys from https://neptun.in.ua/oblasts.geojson; geometry is not used.
local all: { Location } = {
    {
        key = "автономна республіка крим",
        name = "Автономна Республіка Крим",
    },
    { key = "вінницька", name = "Вінницька область" },
    { key = "волинська", name = "Волинська область" },
    {
        key = "дніпропетровська",
        name = "Дніпропетровська область",
    },
    { key = "донецька", name = "Донецька область" },
    { key = "житомирська", name = "Житомирська область" },
    { key = "закарпатська", name = "Закарпатська область" },
    { key = "запорізька", name = "Запорізька область" },
    {
        key = "івано-франківська",
        name = "Івано-Франківська область",
    },
    { key = "кіровоградська", name = "Кіровоградська область" },
    { key = "луганська", name = "Луганська область" },
    { key = "львівська", name = "Львівська область" },
    { key = "миколаївська", name = "Миколаївська область" },
    { key = "одеська", name = "Одеська область" },
    { key = "полтавська", name = "Полтавська область" },
    { key = "рівненська", name = "Рівненська область" },
    { key = "сумська", name = "Сумська область" },
    { key = "тернопільська", name = "Тернопільська область" },
    { key = "харківська", name = "Харківська область" },
    { key = "хмельницька", name = "Хмельницька область" },
    { key = "черкаська", name = "Черкаська область" },
    { key = "чернівецька", name = "Чернівецька область" },
    { key = "чернігівська", name = "Чернігівська область" },
    { key = "херсонська", name = "Херсонська область" },
    { key = "київська", name = "Київська область" },
    { key = "севастополь", name = "Севастополь" },
    { key = "м. київ", name = "м. Київ" },
}

local function find(key: string?): Location?
    for _, location in ipairs(all) do
        if location.key == key then
            return location
        end
    end
    return nil
end

local function displayName(location: Location): string
    local translationKey = "locations." .. location.key
    local translated = noctalia.tr(translationKey)
    return translated == translationKey and location.name or translated
end

return { all = all, find = find, displayName = displayName }
