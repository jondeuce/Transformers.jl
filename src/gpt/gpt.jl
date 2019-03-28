using Flux: @treelike

using ..Basic
using ..Basic: onehot


export Gpt, lmloss
export load_gpt_pretrain

struct Gpt
    pe::PositionEmbedding
    ts::Chain
    drop::Dropout
end

@treelike Gpt

function Gpt(size::Int, head::Int, ps::Int, layer::Int;
             max_len::Int = 512, trainable = true, act = gelu, pdrop = 0.1)
    rem(size, head) != 0 && error("size not divisible by head")
    Gpt(size, head, div(size, head), ps, layer; max_len=max_len, trainable=trainable, act=act, pdrop=pdrop)
end

function Gpt(size::Int, head::Int, hs::Int, ps::Int, layer::Int;
             max_len::Int = 512, trainable = true, act = gelu, pdrop = 0.1)
    Gpt(PositionEmbedding(size, max_len; trainable=trainable),
        Chain([Transformer(size, head, hs, ps; future=false, act=act, pdrop=pdrop) for i = 1:layer]...),
        Dropout(pdrop))
end

function (gpt::Gpt)(x::T, mask=nothing)::T where T
    pe = gpt.pe(x)
    e = x .+ pe
    e = gpt.drop(e)::T
    t = gpt.ts(e)::T
    t = mask === nothing ? t : t .* mask
    t #size(t) == (size, seq_len, batch)
end

function lmloss(embed::Embed, et, t::AbstractMatrix, mask)
    t = t[:, 1:end-1]
    sim = logsoftmax(matmul(embed.embedding * t; transA=true))
    logcrossentropy(et[:, 2:end], sim, mask[:, 2:end])
end

function lmloss(embed::Embed, et, t::ThreeDimArray, mask)::eltype(t)
    t = t[:, 1:end-1, :]
    s = size(t)
    sim = logsoftmax(matmul(embed.embedding, reshape(t, s[1], :); transA=true)) #(vocab, seq_len*batch)
    sim = reshape(sim, :, s[2], s[3])
    logcrossentropy(et[:, 2:end, :], sim, mask[:, 2:end, :])
end

function lmloss(gpt::Gpt, embed::Embed, x)
    e, mask = embed(x)
    t = gpt(e, mask)
    lmloss(embed, onehot(embed, x), t, mask)
end

function Base.show(io::IO, gpt::Gpt)
    hs = div(size(gpt.ts[1].mh.iqproj.W)[1], gpt.ts[1].mh.head)
    h, ps = size(gpt.ts[1].pw.dout.W)

    print(io, "Gpt(")
    print(io, "layers=$(length(gpt.ts.layers)), ")
    print(io, "head=$(gpt.ts[1].mh.head), ")
    print(io, "head_size=$(hs), ")
    print(io, "pwffn_size=$(ps), ")
    print(io, "size=$(h))")
end
