package wg_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"

	"vpn-panel/internal/wg"
)

type ParserSuite struct {
	suite.Suite
}

func (s *ParserSuite) TestParseDump() {

	// фейковый wg dump в реальном формате
	input := `wg0	AAAA1111BBBBCCCCDDDD111122223333444455556666==	preshared	endpoint1	10.8.0.1/32	1700000000	1000	2000	off
wg0	BBBB2222CCCCDDDD111122223333444455556666AAAA==	preshared	endpoint2	10.8.0.2/32	1700000001	3000	4000	off
wg0	CCCC3333DDDD111122223333444455556666AAAA1111==	preshared	(none)	10.8.0.3/32	0	0	0	off`

	peers, err := wg.ParseDump(input)

	assert.NoError(s.T(), err)
	assert.Len(s.T(), peers, 3)

	// peer 1
	assert.Equal(s.T(),
		"AAAA1111BBBBCCCCDDDD111122223333444455556666==",
		peers[0].PublicKey,
	)
	assert.Equal(s.T(), uint64(1000), peers[0].RxBytes)
	assert.Equal(s.T(), uint64(2000), peers[0].TxBytes)

	// peer 2
	assert.Equal(s.T(), uint64(3000), peers[1].RxBytes)
	assert.Equal(s.T(), uint64(4000), peers[1].TxBytes)

	// peer 3 (нулевой трафик)
	assert.Equal(s.T(), uint64(0), peers[2].RxBytes)
	assert.Equal(s.T(), uint64(0), peers[2].TxBytes)
}

func (s *ParserSuite) TestParseHandshake() {

	input := `wg0	AAAA1111BBBBCCCCDDDD111122223333444455556666==	preshared	endpoint	10.8.0.1/32	1700000000	1000	2000	off`

	peers, err := wg.ParseDump(input)

	assert.NoError(s.T(), err)
	assert.Len(s.T(), peers, 1)

	peer := peers[0]

	assert.False(s.T(), peer.LastHandshake.IsZero())

	expected := time.Unix(1700000000, 0).UTC()

	assert.Equal(s.T(), expected, peer.LastHandshake.UTC())
}

func TestParserSuite(t *testing.T) {
	suite.Run(t, new(ParserSuite))
}